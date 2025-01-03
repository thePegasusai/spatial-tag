// Foundation - iOS 15.0+ - Core iOS functionality
import Foundation
// Combine - iOS 15.0+ - Reactive programming support
import Combine

/// EditProfileViewModel manages secure profile editing functionality with comprehensive validation
/// and performance optimization for the Spatial Tag platform.
@MainActor
final class EditProfileViewModel: ViewModelProtocol {
    // MARK: - Published Properties
    
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var error: Error?
    @Published var displayName: String = ""
    @Published var visibilityRadius: Double = 50.0
    @Published var isVisible: Bool = true
    @Published var preferences: [String: Any] = [:]
    @Published private(set) var isValid: Bool = false
    @Published private(set) var formValidation: ValidationState = .idle
    
    // MARK: - Private Properties
    
    private let originalProfile: Profile
    private let securityContext: SecurityContext
    private let logger = Logger.shared
    var cancellables = Set<AnyCancellable>()
    private let performanceMetrics = PerformanceMetrics()
    private let validationQueue = DispatchQueue(label: "com.spatialtag.profilevalidation", qos: .userInitiated)
    
    // MARK: - Validation Constants
    
    private enum ValidationConstants {
        static let minDisplayNameLength = 3
        static let maxDisplayNameLength = 50
        static let minVisibilityRadius = 0.5
        static let maxVisibilityRadius = 50.0
        static let validationDebounceTime = 0.3
    }
    
    // MARK: - Initialization
    
    init(profile: Profile, securityContext: SecurityContext) {
        self.originalProfile = profile
        self.securityContext = securityContext
        
        super.init()
        
        setupInitialState()
        setupValidation()
        setupPerformanceTracking()
    }
    
    // MARK: - Private Setup Methods
    
    private func setupInitialState() {
        displayName = originalProfile.displayName
        visibilityRadius = originalProfile.visibilityRadius
        isVisible = originalProfile.isVisible
        preferences = originalProfile.preferences
        
        logger.debug("Profile edit view model initialized for user: \(originalProfile.id)")
    }
    
    private func setupValidation() {
        // Combine validation publishers with debouncing
        Publishers.CombineLatest4($displayName, $visibilityRadius, $isVisible, $preferences)
            .debounce(for: .seconds(ValidationConstants.validationDebounceTime), scheduler: validationQueue)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] name, radius, visible, prefs in
                self?.validateForm(name: name, radius: radius, visible: visible, preferences: prefs)
            }
            .store(in: &cancellables)
    }
    
    private func setupPerformanceTracking() {
        performanceMetrics.startTracking(operation: "profile_editing")
    }
    
    // MARK: - Validation Methods
    
    private func validateForm(name: String, radius: Double, visible: Bool, preferences: [String: Any]) {
        formValidation = .validating
        
        do {
            // Validate display name
            guard name.count >= ValidationConstants.minDisplayNameLength,
                  name.count <= ValidationConstants.maxDisplayNameLength else {
                throw ValidationError.invalidDisplayName
            }
            
            // Validate visibility radius
            guard radius >= ValidationConstants.minVisibilityRadius,
                  radius <= ValidationConstants.maxVisibilityRadius else {
                throw ValidationError.invalidVisibilityRadius
            }
            
            // Validate preferences
            try validatePreferences(preferences)
            
            // Check for changes
            let hasChanges = name != originalProfile.displayName ||
                           radius != originalProfile.visibilityRadius ||
                           visible != originalProfile.isVisible ||
                           preferences != originalProfile.preferences
            
            isValid = hasChanges
            formValidation = .valid
            
        } catch let validationError {
            isValid = false
            formValidation = .invalid(validationError)
            logger.warning("Profile validation failed: \(validationError)")
        }
    }
    
    private func validatePreferences(_ preferences: [String: Any]) throws {
        for (key, value) in preferences {
            guard key.count <= 50 else {
                throw ValidationError.invalidPreferenceKey
            }
            
            guard value is String || value is Int || value is Double || value is Bool else {
                throw ValidationError.invalidPreferenceValue
            }
        }
    }
    
    // MARK: - Public Methods
    
    /// Saves the updated profile with comprehensive validation and security checks
    /// - Returns: Publisher emitting save result or error
    func saveProfile() -> AnyPublisher<Void, ProfileError> {
        guard isValid else {
            return Fail(error: ProfileError.validationFailed).eraseToAnyPublisher()
        }
        
        isLoading = true
        performanceMetrics.mark(event: "save_started")
        
        return Future { [weak self] promise in
            guard let self = self else {
                promise(.failure(.unknown))
                return
            }
            
            // Create secure profile update
            let profileUpdate = ProfileUpdate(
                id: self.originalProfile.id,
                displayName: self.displayName,
                visibilityRadius: self.visibilityRadius,
                isVisible: self.isVisible,
                preferences: self.preferences
            )
            
            // Validate security context
            guard self.securityContext.validateSession() else {
                self.isLoading = false
                promise(.failure(.unauthorized))
                return
            }
            
            // Submit update
            Task {
                do {
                    try await ProfileService.shared.updateProfile(profileUpdate)
                    
                    self.performanceMetrics.mark(event: "save_completed")
                    self.logger.info("Profile updated successfully: \(self.originalProfile.id)")
                    
                    await MainActor.run {
                        self.isLoading = false
                        promise(.success(()))
                    }
                } catch {
                    self.logger.error("Profile update failed: \(error)")
                    await MainActor.run {
                        self.isLoading = false
                        promise(.failure(.updateFailed))
                    }
                }
            }
        }.eraseToAnyPublisher()
    }
    
    // MARK: - ViewModelProtocol
    
    func onAppear() {
        logger.debug("Profile edit view appeared")
    }
    
    func onDisappear() {
        performanceMetrics.stopTracking()
        cancellables.removeAll()
        logger.debug("Profile edit view disappeared")
    }
}

// MARK: - Supporting Types

extension EditProfileViewModel {
    enum ValidationState {
        case idle
        case validating
        case valid
        case invalid(Error)
    }
    
    enum ValidationError: LocalizedError {
        case invalidDisplayName
        case invalidVisibilityRadius
        case invalidPreferenceKey
        case invalidPreferenceValue
        
        var errorDescription: String? {
            switch self {
            case .invalidDisplayName:
                return "Display name must be between \(ValidationConstants.minDisplayNameLength) and \(ValidationConstants.maxDisplayNameLength) characters"
            case .invalidVisibilityRadius:
                return "Visibility radius must be between \(ValidationConstants.minVisibilityRadius) and \(ValidationConstants.maxVisibilityRadius) meters"
            case .invalidPreferenceKey:
                return "Preference key is too long"
            case .invalidPreferenceValue:
                return "Invalid preference value type"
            }
        }
    }
    
    enum ProfileError: LocalizedError {
        case validationFailed
        case unauthorized
        case updateFailed
        case unknown
        
        var errorDescription: String? {
            switch self {
            case .validationFailed:
                return "Profile validation failed"
            case .unauthorized:
                return "Unauthorized to update profile"
            case .updateFailed:
                return "Failed to update profile"
            case .unknown:
                return "An unknown error occurred"
            }
        }
    }
}