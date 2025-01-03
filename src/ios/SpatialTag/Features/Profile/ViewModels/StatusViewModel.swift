// Foundation - iOS 15.0+ - Basic Swift functionality
import Foundation
// Combine - iOS 15.0+ - Reactive programming support
import Combine

/// ViewModel responsible for managing and observing user status level progression
/// with real-time updates and thread safety in the Profile feature.
@MainActor
final class StatusViewModel: ViewModelProtocol {
    // MARK: - Published Properties
    
    @Published private(set) var currentLevel: StatusLevel = .regular
    @Published private(set) var currentPoints: Int = 0
    @Published private(set) var pointsToNextLevel: Int = 500 // Default to Elite threshold
    @Published private(set) var progressPercentage: Double = 0.0
    @Published var isLoading: Bool = false
    @Published var error: Error?
    
    // MARK: - Private Properties
    
    private var cancellables = Set<AnyCancellable>()
    private var cachedNextLevel: StatusLevel?
    private let userService = UserService.shared
    private let logger = Logger.shared
    
    // MARK: - Initialization
    
    init() {
        setupStatusSubscription()
        logger.debug("StatusViewModel initialized")
    }
    
    // MARK: - Public Methods
    
    /// Updates the current status level and related metrics
    /// - Parameter points: The new point total
    func updateStatus(points: Int) {
        guard points >= 0 else {
            logger.error("Invalid points value: \(points)")
            error = NSError(domain: "com.spatialtag.status", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid points value"])
            return
        }
        
        let startTime = Date()
        
        do {
            // Calculate new status level
            let newLevel = StatusLevel.fromPoints(points)
            currentLevel = newLevel
            currentPoints = points
            
            // Update next level cache
            cachedNextLevel = newLevel.nextLevel
            
            // Calculate points needed for next level
            if let nextLevel = cachedNextLevel {
                pointsToNextLevel = nextLevel.pointThreshold - points
            } else {
                pointsToNextLevel = 0
            }
            
            // Update progress percentage
            progressPercentage = calculateProgressPercentage()
            
            logger.performance("Status update completed",
                             duration: Date().timeIntervalSince(startTime),
                             threshold: 0.1,
                             metadata: [
                                "points": points,
                                "level": newLevel.description,
                                "progress": progressPercentage
                             ])
            
        } catch {
            logger.error("Status update failed: \(error.localizedDescription)")
            self.error = error
        }
    }
    
    /// Resets status tracking and clears cached data
    func resetStatus() {
        cancellables.removeAll()
        currentLevel = .regular
        currentPoints = 0
        pointsToNextLevel = 500
        progressPercentage = 0.0
        cachedNextLevel = nil
        setupStatusSubscription()
        
        logger.debug("Status tracking reset")
    }
    
    // MARK: - ViewModelProtocol
    
    func onAppear() {
        isLoading = true
        userService.pointsPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] points in
                self?.updateStatus(points: points)
                self?.isLoading = false
            }
            .store(in: &cancellables)
    }
    
    func onDisappear() {
        cancellables.removeAll()
    }
    
    // MARK: - Private Methods
    
    private func setupStatusSubscription() {
        userService.pointsPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] points in
                self?.updateStatus(points: points)
            }
            .store(in: &cancellables)
    }
    
    private func calculateProgressPercentage() -> Double {
        guard let nextLevel = cachedNextLevel else {
            return 100.0 // Max level reached
        }
        
        let currentThreshold = currentLevel.pointThreshold
        let nextThreshold = nextLevel.pointThreshold
        let pointsInLevel = currentPoints - currentThreshold
        let pointsNeededForLevel = nextThreshold - currentThreshold
        
        let percentage = (Double(pointsInLevel) / Double(pointsNeededForLevel)) * 100.0
        return min(max(percentage, 0.0), 100.0)
    }
}