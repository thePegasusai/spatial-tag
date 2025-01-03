// Foundation - iOS 15.0+ - Core functionality
import Foundation
// Combine - iOS 15.0+ - Reactive programming
import Combine
// ARKit - 6.0 - High-precision AR functionality
import ARKit

/// ViewModel responsible for managing tag creation state and business logic with enhanced
/// LiDAR-based precision and performance optimization.
@MainActor
final class TagCreationViewModel: ViewModelProtocol {
    // MARK: - Published Properties
    
    @Published var title: String = ""
    @Published var description: String = ""
    @Published var isPublic: Bool = true
    @Published var duration: TimeInterval = 24.0 // Default 24 hours
    @Published var visibilityRadius: Double = 50.0 // Default maximum range
    @Published var mediaData: Data?
    @Published var isValid: Bool = false
    @Published private(set) var batteryImpact: Double = 0.0
    @Published private(set) var placementPrecision: Double = 0.0
    
    // MARK: - ViewModelProtocol Conformance
    
    var isLoading: Bool = false
    var error: Error?
    var cancellables = Set<AnyCancellable>()
    
    // MARK: - Private Properties
    
    private let tagService: TagService
    private let locationManager: LocationManager
    private let arSceneManager: ARSceneManager
    private let logger = Logger(minimumLevel: .debug, category: "TagCreation")
    
    private struct ValidationConstants {
        static let titleMaxLength = 50
        static let descriptionMaxLength = 200
        static let minVisibilityRadius = 0.5
        static let maxVisibilityRadius = 50.0
        static let minDuration: TimeInterval = 1.0
        static let maxDuration: TimeInterval = 24.0
        static let precisionThreshold = 0.01 // 1cm precision
        static let batteryThreshold = 0.15 // 15% maximum impact
    }
    
    // MARK: - Initialization
    
    init(tagService: TagService, locationManager: LocationManager, arSceneManager: ARSceneManager) {
        self.tagService = tagService
        self.locationManager = locationManager
        self.arSceneManager = arSceneManager
        
        super.init()
        setupValidation()
        setupPerformanceMonitoring()
    }
    
    // MARK: - Public Methods
    
    /// Creates a new tag with enhanced precision validation and performance monitoring
    func createTag() -> AnyPublisher<Bool, Error> {
        isLoading = true
        let startTime = CACurrentMediaTime()
        
        return validatePrecision()
            .flatMap { [weak self] isValid -> AnyPublisher<Location, Error> in
                guard let self = self, isValid else {
                    throw ARError.precisionNotMet
                }
                return self.getCurrentLocation()
            }
            .flatMap { [weak self] location -> AnyPublisher<Tag, Error> in
                guard let self = self else { throw ARError.invalidPosition }
                
                return self.tagService.createTag(
                    location: location,
                    content: self.title,
                    visibilityRadius: self.visibilityRadius,
                    expirationHours: self.duration
                )
            }
            .flatMap { [weak self] tag -> AnyPublisher<Bool, Error> in
                guard let self = self else { throw ARError.invalidPosition }
                
                return self.placeTagInAR(tag)
            }
            .handleEvents(
                receiveCompletion: { [weak self] completion in
                    self?.isLoading = false
                    if case .failure(let error) = completion {
                        self?.handleError(error)
                    }
                    
                    // Log performance metrics
                    let endTime = CACurrentMediaTime()
                    self?.logger.performance(
                        "Tag Creation",
                        duration: endTime - startTime,
                        threshold: 1.0,
                        metadata: [
                            "batteryImpact": self?.batteryImpact ?? 0.0,
                            "precision": self?.placementPrecision ?? 0.0
                        ]
                    )
                }
            )
            .eraseToAnyPublisher()
    }
    
    // MARK: - Private Methods
    
    private func setupValidation() {
        Publishers.CombineLatest4(
            $title,
            $description,
            $visibilityRadius,
            $duration
        )
        .map { [weak self] title, description, radius, duration -> Bool in
            guard let self = self else { return false }
            
            // Validate input constraints
            let isTitleValid = !title.isEmpty && title.count <= ValidationConstants.titleMaxLength
            let isDescriptionValid = description.count <= ValidationConstants.descriptionMaxLength
            let isRadiusValid = radius >= ValidationConstants.minVisibilityRadius && 
                              radius <= ValidationConstants.maxVisibilityRadius
            let isDurationValid = duration >= ValidationConstants.minDuration && 
                                duration <= ValidationConstants.maxDuration
            
            // Validate performance metrics
            let isPrecisionValid = self.placementPrecision <= ValidationConstants.precisionThreshold
            let isBatteryValid = self.batteryImpact <= ValidationConstants.batteryThreshold
            
            return isTitleValid && isDescriptionValid && isRadiusValid && 
                   isDurationValid && isPrecisionValid && isBatteryValid
        }
        .assign(to: &$isValid)
    }
    
    private func setupPerformanceMonitoring() {
        // Monitor battery impact
        Timer.publish(every: 1.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.updateBatteryImpact()
            }
            .store(in: &cancellables)
    }
    
    private func validatePrecision() -> AnyPublisher<Bool, Error> {
        Future { [weak self] promise in
            guard let self = self else {
                promise(.failure(ARError.invalidPosition))
                return
            }
            
            self.arSceneManager.validatePrecision()
                .sink(
                    receiveCompletion: { completion in
                        if case .failure(let error) = completion {
                            promise(.failure(error))
                        }
                    },
                    receiveValue: { precision in
                        self.placementPrecision = precision
                        promise(.success(precision <= ValidationConstants.precisionThreshold))
                    }
                )
                .store(in: &self.cancellables)
        }
        .eraseToAnyPublisher()
    }
    
    private func getCurrentLocation() -> AnyPublisher<Location, Error> {
        Future { [weak self] promise in
            guard let self = self else {
                promise(.failure(LocationError.invalidLocation))
                return
            }
            
            self.locationManager.startUpdatingLocation()
                .first()
                .sink(
                    receiveCompletion: { completion in
                        if case .failure(let error) = completion {
                            promise(.failure(error))
                        }
                    },
                    receiveValue: { location in
                        promise(.success(location))
                    }
                )
                .store(in: &self.cancellables)
        }
        .eraseToAnyPublisher()
    }
    
    private func placeTagInAR(_ tag: Tag) -> AnyPublisher<Bool, Error> {
        Future { [weak self] promise in
            guard let self = self else {
                promise(.failure(ARError.invalidPosition))
                return
            }
            
            // Get current AR frame for placement
            guard let frame = self.arSceneManager.currentFrame else {
                promise(.failure(ARError.invalidPosition))
                return
            }
            
            // Calculate placement position using LiDAR
            let position = simd_float4(frame.camera.transform.columns.3)
            
            switch self.arSceneManager.placeTag(tag, position: position) {
            case .success:
                promise(.success(true))
            case .failure(let error):
                promise(.failure(error))
            }
        }
        .eraseToAnyPublisher()
    }
    
    private func updateBatteryImpact() {
        let currentLevel = UIDevice.current.batteryLevel
        if currentLevel > 0 {
            batteryImpact = 1.0 - Double(currentLevel)
        }
    }
    
    private func handleError(_ error: Error) {
        self.error = error
        logger.error("Tag creation failed: \(error.localizedDescription)")
    }
    
    // MARK: - ViewModelProtocol Implementation
    
    func onAppear() {
        // Start monitoring when view appears
        setupPerformanceMonitoring()
    }
    
    func onDisappear() {
        // Cleanup when view disappears
        cancellables.removeAll()
    }
}