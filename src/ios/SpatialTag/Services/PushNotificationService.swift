// Foundation - Core iOS functionality
import Foundation
// UserNotifications - iOS 15.0+ - Core push notification functionality
import UserNotifications
// Firebase/Messaging - v10.0.0 - Firebase Cloud Messaging integration
import FirebaseMessaging
// BackgroundTasks - iOS 15.0+ - Background task handling
import BackgroundTasks
// CryptoKit - iOS 15.0+ - Secure payload encryption
import CryptoKit

// MARK: - Constants

private let NOTIFICATION_CATEGORIES = [
    "tag_nearby": "tag_nearby",
    "user_nearby": "user_nearby",
    "tag_interaction": "tag_interaction",
    "status_update": "status_update"
]

private let NOTIFICATION_ACTIONS = [
    "view_tag": "view_tag",
    "view_profile": "view_profile",
    "respond": "respond",
    "dismiss": "dismiss"
]

private let BACKGROUND_TASK_IDENTIFIERS = [
    "notification_refresh": "com.spatialtag.notification.refresh",
    "token_update": "com.spatialtag.notification.token"
]

// MARK: - NotificationPreferences

private struct NotificationPreferences {
    var isEnabled: Bool
    var allowLocationBasedAlerts: Bool
    var allowTagAlerts: Bool
    var allowStatusUpdates: Bool
    var quietHoursStart: Date?
    var quietHoursEnd: Date?
}

// MARK: - PushNotificationService

@objc
public class PushNotificationService: NSObject {
    
    // MARK: - Properties
    
    private let notificationCenter: UNUserNotificationCenter
    private let messaging: Messaging
    private let logger: Logger
    private let backgroundTaskScheduler: BGTaskScheduler
    private var fcmToken: String?
    private var preferences: NotificationPreferences
    private let encryptionKey: SymmetricKey
    
    // MARK: - Initialization
    
    override init() {
        self.notificationCenter = UNUserNotificationCenter.current()
        self.messaging = Messaging.messaging()
        self.logger = Logger.shared
        self.backgroundTaskScheduler = BGTaskScheduler.shared
        self.preferences = NotificationPreferences(
            isEnabled: false,
            allowLocationBasedAlerts: true,
            allowTagAlerts: true,
            allowStatusUpdates: true
        )
        self.encryptionKey = SymmetricKey(size: .bits256)
        
        super.init()
        
        configureNotificationCategories()
        configureBackgroundTasks()
        messaging.delegate = self
        notificationCenter.delegate = self
        
        logger.debug("PushNotificationService initialized")
    }
    
    // MARK: - Public Methods
    
    public func registerForPushNotifications(completion: @escaping (Result<Bool, Error>) -> Void) {
        let startTime = DispatchTime.now()
        
        let options: UNAuthorizationOptions = [.alert, .sound, .badge]
        
        notificationCenter.requestAuthorization(options: options) { [weak self] granted, error in
            guard let self = self else { return }
            
            if let error = error {
                self.logger.error("Failed to request notification authorization: \(error.localizedDescription)")
                completion(.failure(error))
                return
            }
            
            if granted {
                self.preferences.isEnabled = true
                DispatchQueue.main.async {
                    UIApplication.shared.registerForRemoteNotifications()
                }
                
                // Log performance metrics
                let endTime = DispatchTime.now()
                let elapsedTime = Double(endTime.uptimeNanoseconds - startTime.uptimeNanoseconds) / 1_000_000
                self.logger.performance("Push notification registration", duration: elapsedTime)
                
                completion(.success(true))
            } else {
                self.logger.warning("Push notification authorization denied")
                completion(.success(false))
            }
        }
    }
    
    public func handleNotification(_ notification: UNNotification) {
        let startTime = DispatchTime.now()
        
        do {
            // Decrypt and validate payload
            guard let encryptedPayload = notification.request.content.userInfo["payload"] as? Data,
                  let decryptedData = try? decryptPayload(encryptedPayload),
                  let payload = try? JSONSerialization.jsonObject(with: decryptedData) as? [String: Any] else {
                logger.error("Invalid notification payload")
                return
            }
            
            // Process based on category
            switch notification.request.content.categoryIdentifier {
            case NOTIFICATION_CATEGORIES["tag_nearby"]:
                handleTagNearbyNotification(payload)
                
            case NOTIFICATION_CATEGORIES["user_nearby"]:
                handleUserNearbyNotification(payload)
                
            case NOTIFICATION_CATEGORIES["tag_interaction"]:
                handleTagInteractionNotification(payload)
                
            case NOTIFICATION_CATEGORIES["status_update"]:
                handleStatusUpdateNotification(payload)
                
            default:
                logger.warning("Unknown notification category")
            }
            
            // Log performance metrics
            let endTime = DispatchTime.now()
            let elapsedTime = Double(endTime.uptimeNanoseconds - startTime.uptimeNanoseconds) / 1_000_000
            logger.performance("Notification handling", duration: elapsedTime)
            
        } catch {
            logger.error("Failed to handle notification: \(error.localizedDescription)")
        }
    }
    
    public func updateFCMToken(_ token: String) {
        let startTime = DispatchTime.now()
        
        do {
            // Encrypt token before storage
            let tokenData = Data(token.utf8)
            let encryptedToken = try encryptPayload(tokenData)
            
            fcmToken = token
            UserDefaults.standard.set(encryptedToken, forKey: "fcm_token")
            
            // Schedule background refresh
            scheduleTokenRefresh()
            
            let endTime = DispatchTime.now()
            let elapsedTime = Double(endTime.uptimeNanoseconds - startTime.uptimeNanoseconds) / 1_000_000
            logger.performance("Token update", duration: elapsedTime)
            
        } catch {
            logger.error("Failed to update FCM token: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Private Methods
    
    private func configureNotificationCategories() {
        var categories = Set<UNNotificationCategory>()
        
        // Tag nearby category
        let tagNearbyCategory = UNNotificationCategory(
            identifier: NOTIFICATION_CATEGORIES["tag_nearby"]!,
            actions: [
                UNNotificationAction(
                    identifier: NOTIFICATION_ACTIONS["view_tag"]!,
                    title: "View Tag",
                    options: .foreground
                ),
                UNNotificationAction(
                    identifier: NOTIFICATION_ACTIONS["dismiss"]!,
                    title: "Dismiss",
                    options: .destructive
                )
            ],
            intentIdentifiers: [],
            options: .customDismissAction
        )
        categories.insert(tagNearbyCategory)
        
        // User nearby category
        let userNearbyCategory = UNNotificationCategory(
            identifier: NOTIFICATION_CATEGORIES["user_nearby"]!,
            actions: [
                UNNotificationAction(
                    identifier: NOTIFICATION_ACTIONS["view_profile"]!,
                    title: "View Profile",
                    options: .foreground
                ),
                UNNotificationAction(
                    identifier: NOTIFICATION_ACTIONS["dismiss"]!,
                    title: "Dismiss",
                    options: .destructive
                )
            ],
            intentIdentifiers: [],
            options: .customDismissAction
        )
        categories.insert(userNearbyCategory)
        
        notificationCenter.setNotificationCategories(categories)
    }
    
    private func configureBackgroundTasks() {
        backgroundTaskScheduler.register(
            forTaskWithIdentifier: BACKGROUND_TASK_IDENTIFIERS["notification_refresh"]!,
            using: nil
        ) { task in
            self.handleBackgroundRefresh(task as! BGAppRefreshTask)
        }
        
        backgroundTaskScheduler.register(
            forTaskWithIdentifier: BACKGROUND_TASK_IDENTIFIERS["token_update"]!,
            using: nil
        ) { task in
            self.handleTokenRefresh(task as! BGAppRefreshTask)
        }
    }
    
    private func handleBackgroundRefresh(_ task: BGAppRefreshTask) {
        let startTime = DispatchTime.now()
        
        task.expirationHandler = {
            task.setTaskCompleted(success: false)
        }
        
        // Perform refresh operations
        // Schedule next refresh
        scheduleBackgroundRefresh()
        
        let endTime = DispatchTime.now()
        let elapsedTime = Double(endTime.uptimeNanoseconds - startTime.uptimeNanoseconds) / 1_000_000
        logger.performance("Background refresh", duration: elapsedTime)
        
        task.setTaskCompleted(success: true)
    }
    
    private func handleTokenRefresh(_ task: BGAppRefreshTask) {
        task.expirationHandler = {
            task.setTaskCompleted(success: false)
        }
        
        messaging.token { [weak self] token, error in
            guard let self = self else { return }
            
            if let error = error {
                self.logger.error("Token refresh failed: \(error.localizedDescription)")
                task.setTaskCompleted(success: false)
                return
            }
            
            if let token = token {
                self.updateFCMToken(token)
            }
            
            task.setTaskCompleted(success: true)
        }
    }
    
    private func scheduleBackgroundRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: BACKGROUND_TASK_IDENTIFIERS["notification_refresh"]!)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60) // 15 minutes
        
        do {
            try backgroundTaskScheduler.submit(request)
        } catch {
            logger.error("Failed to schedule background refresh: \(error.localizedDescription)")
        }
    }
    
    private func scheduleTokenRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: BACKGROUND_TASK_IDENTIFIERS["token_update"]!)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 60 * 60) // 1 hour
        
        do {
            try backgroundTaskScheduler.submit(request)
        } catch {
            logger.error("Failed to schedule token refresh: \(error.localizedDescription)")
        }
    }
    
    private func encryptPayload(_ data: Data) throws -> Data {
        return try ChaChaPoly.seal(data, using: encryptionKey).combined
    }
    
    private func decryptPayload(_ data: Data) throws -> Data {
        let sealedBox = try ChaChaPoly.SealedBox(combined: data)
        return try ChaChaPoly.open(sealedBox, using: encryptionKey)
    }
    
    // MARK: - Notification Handlers
    
    private func handleTagNearbyNotification(_ payload: [String: Any]) {
        guard preferences.allowTagAlerts,
              let tagData = payload["tag"] as? [String: Any],
              let tagId = tagData["id"] as? String else {
            return
        }
        
        logger.debug("Processing nearby tag notification: \(tagId)")
        // Process tag data and update UI
    }
    
    private func handleUserNearbyNotification(_ payload: [String: Any]) {
        guard preferences.allowLocationBasedAlerts,
              let userData = payload["user"] as? [String: Any],
              let userId = userData["id"] as? String else {
            return
        }
        
        logger.debug("Processing nearby user notification: \(userId)")
        // Process user data and update UI
    }
    
    private func handleTagInteractionNotification(_ payload: [String: Any]) {
        guard preferences.allowTagAlerts,
              let interactionData = payload["interaction"] as? [String: Any],
              let tagId = interactionData["tagId"] as? String else {
            return
        }
        
        logger.debug("Processing tag interaction notification: \(tagId)")
        // Process interaction data and update UI
    }
    
    private func handleStatusUpdateNotification(_ payload: [String: Any]) {
        guard preferences.allowStatusUpdates,
              let statusData = payload["status"] as? [String: Any],
              let newStatus = statusData["level"] as? String else {
            return
        }
        
        logger.debug("Processing status update notification: \(newStatus)")
        // Process status update and update UI
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension PushNotificationService: UNUserNotificationCenterDelegate {
    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        handleNotification(notification)
        completionHandler([.banner, .sound])
    }
    
    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        handleNotification(response.notification)
        completionHandler()
    }
}

// MARK: - MessagingDelegate

extension PushNotificationService: MessagingDelegate {
    public func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        if let token = fcmToken {
            updateFCMToken(token)
        }
    }
}