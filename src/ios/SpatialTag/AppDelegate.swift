import UIKit
import Combine
import Firebase
import UserNotifications
import BackgroundTasks
import FirebaseAnalytics

@main
class AppDelegate: UIResponder, UIApplicationDelegate {
    
    // MARK: - Properties
    
    var window: UIWindow?
    private var coordinator: AppCoordinator?
    private let pushNotificationService = PushNotificationService()
    private var cancellables = Set<AnyCancellable>()
    private let logger = Logger(subsystem: "com.spatialtag.app", category: "AppDelegate")
    
    // MARK: - App Lifecycle
    
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        logger.debug("Application launching")
        
        // Configure Firebase
        do {
            try configureFirebase()
        } catch {
            logger.error("Firebase configuration failed: \(error.localizedDescription)")
            return false
        }
        
        // Configure core services
        configureServices()
        
        // Configure window and coordinator
        configureWindow()
        
        // Configure push notifications
        configurePushNotifications()
        
        // Configure background tasks
        configureBackgroundTasks()
        
        logger.info("Application launch completed successfully")
        return true
    }
    
    func applicationWillResignActive(_ application: UIApplication) {
        logger.debug("Application will resign active")
        coordinator?.stopARSession()
    }
    
    func applicationDidEnterBackground(_ application: UIApplication) {
        logger.debug("Application entered background")
        scheduleBackgroundTasks()
    }
    
    func applicationWillEnterForeground(_ application: UIApplication) {
        logger.debug("Application will enter foreground")
        AppContainer.shared.validateServices()
    }
    
    func applicationDidBecomeActive(_ application: UIApplication) {
        logger.debug("Application became active")
        coordinator?.startARSession()
        UIApplication.shared.applicationIconBadgeNumber = 0
    }
    
    // MARK: - Push Notifications
    
    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        let tokenString = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
        logger.debug("Registered for push notifications with token: \(tokenString)")
        pushNotificationService.updateFCMToken(tokenString)
    }
    
    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        logger.error("Failed to register for push notifications: \(error.localizedDescription)")
    }
    
    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        logger.debug("Received remote notification")
        pushNotificationService.handleNotification(userInfo)
        completionHandler(.newData)
    }
    
    // MARK: - Background Tasks
    
    func application(
        _ application: UIApplication,
        handleEventsForBackgroundURLSession identifier: String,
        completionHandler: @escaping () -> Void
    ) {
        logger.debug("Handling background URL session: \(identifier)")
        completionHandler()
    }
    
    // MARK: - State Restoration
    
    func application(
        _ application: UIApplication,
        shouldRestoreSecureApplicationState coder: NSCoder
    ) -> Bool {
        logger.debug("Should restore secure application state")
        return true
    }
    
    func application(
        _ application: UIApplication,
        shouldSaveSecureApplicationState coder: NSCoder
    ) -> Bool {
        logger.debug("Should save secure application state")
        return true
    }
    
    // MARK: - Private Methods
    
    private func configureFirebase() throws {
        FirebaseApp.configure()
        Analytics.setAnalyticsCollectionEnabled(true)
    }
    
    private func configureServices() {
        AppContainer.shared.configureServices()
    }
    
    private func configureWindow() {
        window = UIWindow(frame: UIScreen.main.bounds)
        let navigationController = UINavigationController()
        coordinator = AppCoordinator(window: window!)
        window?.rootViewController = navigationController
        coordinator?.start()
        window?.makeKeyAndVisible()
    }
    
    private func configurePushNotifications() {
        pushNotificationService.registerForPushNotifications { [weak self] result in
            switch result {
            case .success:
                self?.logger.info("Push notification registration successful")
            case .failure(let error):
                self?.logger.error("Push notification registration failed: \(error.localizedDescription)")
            }
        }
    }
    
    private func configureBackgroundTasks() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: "com.spatialtag.refresh",
            using: nil
        ) { task in
            self.handleBackgroundRefresh(task as! BGAppRefreshTask)
        }
    }
    
    private func scheduleBackgroundTasks() {
        let request = BGAppRefreshTaskRequest(identifier: "com.spatialtag.refresh")
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        
        do {
            try BGTaskScheduler.shared.submit(request)
            logger.debug("Background task scheduled successfully")
        } catch {
            logger.error("Failed to schedule background task: \(error.localizedDescription)")
        }
    }
    
    private func handleBackgroundRefresh(_ task: BGAppRefreshTask) {
        task.expirationHandler = {
            task.setTaskCompleted(success: false)
        }
        
        AppContainer.shared.refreshServices()
            .sink(
                receiveCompletion: { [weak self] completion in
                    if case .failure(let error) = completion {
                        self?.logger.error("Background refresh failed: \(error.localizedDescription)")
                        task.setTaskCompleted(success: false)
                    }
                },
                receiveValue: { [weak self] _ in
                    self?.logger.debug("Background refresh completed successfully")
                    task.setTaskCompleted(success: true)
                }
            )
            .store(in: &cancellables)
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension AppDelegate: UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        pushNotificationService.handleNotification(notification)
        completionHandler([.banner, .sound])
    }
    
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        pushNotificationService.handleNotification(response.notification)
        completionHandler()
    }
}