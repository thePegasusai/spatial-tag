// Foundation - iOS 15.0+ - Core functionality
import Foundation
// Combine - iOS 15.0+ - Reactive programming support
import Combine

/// Thread-safe ViewModel managing the detailed view of a spatial tag with performance optimization
@MainActor
final class TagDetailViewModel: ViewModelProtocol {
    // MARK: - Published Properties
    
    private let tag: Tag
    @Published private(set) var isWithinRange: Bool = false
    @Published private(set) var canInteract: Bool = false
    @Published private(set) var isOwner: Bool = false
    @Published private(set) var timeRemaining: TimeInterval = 0
    @Published private(set) var interactionCount: Int = 0
    @Published private(set) var isLoading: Bool = false
    @Published var error: Error?
    
    // MARK: - Private Properties
    
    private let locationManager: LocationManager
    private let tagService: TagService
    private var cancellables = Set<AnyCancellable>()
    private var updateTimer: DispatchWorkItem?
    private var retryCount: Int = 0
    private let maxRetries: Int = 3
    private let performanceThreshold: TimeInterval = 0.1
    private let logger = Logger.shared
    
    // MARK: - Initialization
    
    init(tag: Tag) {
        self.tag = tag
        self.locationManager = LocationManager()
        self.tagService = TagService.shared
        
        setupMonitoring()
        startLocationUpdates()
        validatePermissions()
    }
    
    // MARK: - Public Methods
    
    /// Records an interaction with the tag using rate limiting and caching
    func interactWithTag() -> AnyPublisher<Void, Error> {
        let startTime = DispatchTime.now()
        
        guard canInteract else {
            return Fail(error: LocationError.outOfRange).eraseToAnyPublisher()
        }
        
        isLoading = true
        
        return tagService.interactWithTag(tag.id)
            .handleEvents(
                receiveCompletion: { [weak self] completion in
                    self?.isLoading = false
                    
                    // Log performance metrics
                    let endTime = DispatchTime.now()
                    let elapsed = Double(endTime.uptimeNanoseconds - startTime.uptimeNanoseconds) / 1_000_000
                    
                    self?.logger.performance("Tag Interaction",
                                          duration: elapsed,
                                          threshold: self?.performanceThreshold,
                                          metadata: ["tagId": self?.tag.id.uuidString ?? ""])
                },
                receiveOutput: { [weak self] _ in
                    self?.interactionCount += 1
                }
            )
            .retry(maxRetries) { error -> AnyPublisher<Void, Error> in
                return Just(())
                    .delay(for: .seconds(pow(2.0, Double($0))), scheduler: DispatchQueue.global())
                    .setFailureType(to: Error.self)
                    .eraseToAnyPublisher()
            }
            .eraseToAnyPublisher()
    }
    
    /// Deletes the tag with permission verification and cleanup
    func deleteTag() -> AnyPublisher<Void, Error> {
        guard isOwner else {
            return Fail(error: APIError.forbidden).eraseToAnyPublisher()
        }
        
        isLoading = true
        
        return tagService.deleteTag(tag.id)
            .handleEvents(receiveCompletion: { [weak self] completion in
                self?.isLoading = false
                if case .finished = completion {
                    self?.cleanup()
                }
            })
            .eraseToAnyPublisher()
    }
    
    // MARK: - ViewModelProtocol Implementation
    
    func onAppear() {
        setupMonitoring()
        startLocationUpdates()
    }
    
    func onDisappear() {
        cleanup()
    }
    
    // MARK: - Private Methods
    
    private func setupMonitoring() {
        // Monitor location updates for range calculation
        locationManager.startUpdatingLocation()
            .sink(
                receiveCompletion: { [weak self] completion in
                    if case .failure(let error) = completion {
                        self?.handleError(error)
                    }
                },
                receiveValue: { [weak self] location in
                    self?.updateRangeStatus(with: location)
                }
            )
            .store(in: &cancellables)
        
        // Setup timer for expiration updates
        scheduleExpirationUpdates()
    }
    
    private func startLocationUpdates() {
        locationManager.requestLocationPermission()
            .sink(
                receiveCompletion: { [weak self] completion in
                    if case .failure(let error) = completion {
                        self?.handleError(error)
                    }
                },
                receiveValue: { _ in }
            )
            .store(in: &cancellables)
    }
    
    private func updateRangeStatus(with location: Location) {
        let startTime = DispatchTime.now()
        
        isWithinRange = tag.isWithinRange(location)
        canInteract = isWithinRange && !tag.isExpired()
        
        // Log performance metrics
        let endTime = DispatchTime.now()
        let elapsed = Double(endTime.uptimeNanoseconds - startTime.uptimeNanoseconds) / 1_000_000
        
        logger.performance("Range Status Update",
                         duration: elapsed,
                         threshold: performanceThreshold,
                         metadata: ["tagId": tag.id.uuidString])
    }
    
    private func scheduleExpirationUpdates() {
        updateTimer?.cancel()
        
        let workItem = DispatchWorkItem { [weak self] in
            self?.updateTimeRemaining()
        }
        
        updateTimer = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: workItem)
    }
    
    private func updateTimeRemaining() {
        let now = Date()
        timeRemaining = tag.expiresAt.timeIntervalSince(now)
        
        if timeRemaining > 0 {
            scheduleExpirationUpdates()
        } else {
            canInteract = false
        }
    }
    
    private func validatePermissions() {
        isOwner = tag.creatorId == User.current?.id
    }
    
    private func cleanup() {
        updateTimer?.cancel()
        updateTimer = nil
        locationManager.stopUpdatingLocation()
        cancellables.removeAll()
    }
    
    private func handleError(_ error: Error) {
        self.error = error
        self.isLoading = false
        logger.error("TagDetailViewModel error: \(error.localizedDescription)",
                    metadata: ["tagId": tag.id.uuidString])
    }
}