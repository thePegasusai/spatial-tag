//
// CoreDataStack.swift
// SpatialTag
//
// Thread-safe Core Data stack implementation with advanced caching
// and performance optimization for the Spatial Tag application
//

import CoreData // iOS 15.0+
import Foundation // iOS 15.0+
import os.log // iOS 15.0+

// MARK: - Constants

private let MODEL_NAME = "SpatialTag"
private let SQLITE_STORE_TYPE = NSSQLiteStoreType
private let CACHE_CLEANUP_INTERVAL: TimeInterval = 300 // 5 minutes
private let MAX_BATCH_SIZE = 500

// MARK: - Error Types

enum CoreDataError: Error {
    case modelNotFound
    case storeConfigurationFailed
    case saveFailed
    case batchOperationFailed
    case mergeConflict
}

// MARK: - CoreDataStack

public final class CoreDataStack {
    
    // MARK: - Properties
    
    public static let shared = CoreDataStack()
    
    private(set) var container: NSPersistentContainer
    public private(set) var viewContext: NSManagedObjectContext
    private var backgroundContext: NSManagedObjectContext
    private let logger = Logger(minimumLevel: .debug, category: "CoreData")
    private let backgroundQueue = DispatchQueue(label: "com.spatialtag.coredata.background",
                                              qos: .utility)
    
    // MARK: - Initialization
    
    private init() {
        guard let modelURL = Bundle.main.url(forResource: MODEL_NAME, withExtension: "momd"),
              let model = NSManagedObjectModel(contentsOf: modelURL) else {
            fatalError("Core Data model not found")
        }
        
        // Initialize container with performance optimizations
        container = NSPersistentContainer(name: MODEL_NAME, managedObjectModel: model)
        
        // Configure store options for optimal performance
        let storeDescription = NSPersistentStoreDescription()
        storeDescription.type = SQLITE_STORE_TYPE
        storeDescription.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
        storeDescription.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        
        // Performance optimizations
        storeDescription.setOption(true as NSNumber, forKey: NSPersistentStoreOption.shouldMigrateStoreAutomaticallyKey)
        storeDescription.setOption(true as NSNumber, forKey: NSPersistentStoreOption.shouldInferMappingModelAutomaticallyKey)
        
        // Configure SQLite pragmas for better performance
        var pragmas: [String: String] = [
            "journal_mode": "WAL",
            "synchronous": "NORMAL",
            "auto_vacuum": "INCREMENTAL",
            "cache_size": "2000"
        ]
        storeDescription.setOption(pragmas as NSDictionary, forKey: NSSQLitePragmasOption)
        
        container.persistentStoreDescriptions = [storeDescription]
        
        // Load persistent stores
        container.loadPersistentStores { [weak self] description, error in
            if let error = error {
                self?.logger.error("Failed to load persistent stores: \(error.localizedDescription)")
                fatalError("Core Data store failed to load")
            }
            self?.logger.info("Persistent store loaded successfully")
        }
        
        // Configure view context
        viewContext = container.viewContext
        viewContext.automaticallyMergesChangesFromParent = true
        viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        viewContext.shouldDeleteInaccessibleFaults = true
        
        // Configure background context
        backgroundContext = container.newBackgroundContext()
        backgroundContext.mergePolicy = NSMergeByPropertyStoreTrumpMergePolicy
        backgroundContext.shouldDeleteInaccessibleFaults = true
        
        // Set up automatic cache cleanup
        setupAutomaticCacheCleanup()
        
        logger.debug("CoreDataStack initialized successfully")
    }
    
    // MARK: - Public Methods
    
    /// Saves changes in the specified context with error handling and performance tracking
    @discardableResult
    public func saveContext(_ context: NSManagedObjectContext) async throws -> Bool {
        guard context.hasChanges else { return true }
        
        let startTime = DispatchTime.now()
        
        do {
            try await context.perform {
                try context.save()
            }
            
            // Log performance metrics
            let endTime = DispatchTime.now()
            let duration = Double(endTime.uptimeNanoseconds - startTime.uptimeNanoseconds) / 1_000_000 // Convert to milliseconds
            
            logger.performance("CoreData.saveContext",
                             duration: duration,
                             threshold: 100,
                             metadata: ["changedObjects": context.insertedObjects.count + context.updatedObjects.count + context.deletedObjects.count])
            
            return true
        } catch {
            logger.error("Failed to save context: \(error.localizedDescription)")
            throw CoreDataError.saveFailed
        }
    }
    
    /// Executes a task in a background context with performance optimization
    public func performBackgroundTask<T>(_ task: @escaping (NSManagedObjectContext) throws -> T) async throws -> T {
        let context = container.newBackgroundContext()
        context.mergePolicy = NSMergeByPropertyStoreTrumpMergePolicy
        
        let startTime = DispatchTime.now()
        
        do {
            let result = try await context.perform {
                try task(context)
            }
            
            // Log performance metrics
            let endTime = DispatchTime.now()
            let duration = Double(endTime.uptimeNanoseconds - startTime.uptimeNanoseconds) / 1_000_000
            
            logger.performance("CoreData.backgroundTask",
                             duration: duration,
                             threshold: 200)
            
            return result
        } catch {
            logger.error("Background task failed: \(error.localizedDescription)")
            throw error
        }
    }
    
    /// Removes expired data based on cache strategy
    public func clearExpiredData() async throws {
        try await performBackgroundTask { context in
            let startTime = DispatchTime.now()
            var deletedCount = 0
            
            // Clear expired tags
            let tagFetch: NSFetchRequest<NSFetchRequestResult> = NSFetchRequest(entityName: "Tag")
            tagFetch.predicate = NSPredicate(format: "expirationDate < %@", Date() as NSDate)
            
            let tagDelete = NSBatchDeleteRequest(fetchRequest: tagFetch)
            tagDelete.resultType = .resultTypeObjectIDs
            
            if let result = try context.execute(tagDelete) as? NSBatchDeleteResult,
               let objectIDs = result.result as? [NSManagedObjectID] {
                NSManagedObjectContext.mergeChanges(fromRemoteContextSave: [NSDeletedObjectsKey: objectIDs],
                                                  into: [self.viewContext])
                deletedCount += objectIDs.count
            }
            
            // Clear old location data (>30s)
            let locationFetch: NSFetchRequest<NSFetchRequestResult> = NSFetchRequest(entityName: "Location")
            locationFetch.predicate = NSPredicate(format: "timestamp < %@",
                                                Date().addingTimeInterval(-30) as NSDate)
            
            let locationDelete = NSBatchDeleteRequest(fetchRequest: locationFetch)
            locationDelete.resultType = .resultTypeObjectIDs
            
            if let result = try context.execute(locationDelete) as? NSBatchDeleteResult,
               let objectIDs = result.result as? [NSManagedObjectID] {
                NSManagedObjectContext.mergeChanges(fromRemoteContextSave: [NSDeletedObjectsKey: objectIDs],
                                                  into: [self.viewContext])
                deletedCount += objectIDs.count
            }
            
            // Clear expired profile cache (>1h)
            let profileFetch: NSFetchRequest<NSFetchRequestResult> = NSFetchRequest(entityName: "Profile")
            profileFetch.predicate = NSPredicate(format: "lastUpdated < %@",
                                               Date().addingTimeInterval(-3600) as NSDate)
            
            let profileDelete = NSBatchDeleteRequest(fetchRequest: profileFetch)
            profileDelete.resultType = .resultTypeObjectIDs
            
            if let result = try context.execute(profileDelete) as? NSBatchDeleteResult,
               let objectIDs = result.result as? [NSManagedObjectID] {
                NSManagedObjectContext.mergeChanges(fromRemoteContextSave: [NSDeletedObjectsKey: objectIDs],
                                                  into: [self.viewContext])
                deletedCount += objectIDs.count
            }
            
            // Log cleanup metrics
            let endTime = DispatchTime.now()
            let duration = Double(endTime.uptimeNanoseconds - startTime.uptimeNanoseconds) / 1_000_000
            
            logger.performance("CoreData.clearExpiredData",
                             duration: duration,
                             metadata: ["deletedObjects": deletedCount])
        }
    }
    
    // MARK: - Private Methods
    
    private func setupAutomaticCacheCleanup() {
        backgroundQueue.async { [weak self] in
            guard let self = self else { return }
            
            while true {
                do {
                    try Task.checkCancellation()
                    try await self.clearExpiredData()
                    try await Task.sleep(nanoseconds: UInt64(CACHE_CLEANUP_INTERVAL * 1_000_000_000))
                } catch {
                    self.logger.error("Cache cleanup failed: \(error.localizedDescription)")
                }
            }
        }
    }
}