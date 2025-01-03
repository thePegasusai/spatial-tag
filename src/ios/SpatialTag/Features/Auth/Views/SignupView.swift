// SwiftUI - iOS 15.0+ - Core UI framework
import SwiftUI
// Combine - iOS 15.0+ - Reactive programming
import Combine
// LocalAuthentication - iOS 15.0+ - Biometric auth
import LocalAuthentication

/// A secure and accessible signup view implementing WCAG 2.1 AA compliance
struct SignupView: View {
    // MARK: - Properties
    
    @StateObject private var viewModel: SignupViewModel
    
    @FocusState private var focusedField: Field?
    
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.dismiss) private var dismiss
    
    // MARK: - Constants
    
    private enum Constants {
        static let spacing: CGFloat = 20
        static let cornerRadius: CGFloat = 12
        static let fieldHeight: CGFloat = 50
        static let iconSize: CGFloat = 24
    }
    
    // MARK: - Initialization
    
    init(viewModel: SignupViewModel = SignupViewModel()) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }
    
    // MARK: - Body
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: Constants.spacing) {
                    // App Logo
                    Image("app-logo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 120, height: 120)
                        .accessibilityHidden(true)
                    
                    // Title
                    Text("Create Account")
                        .font(.largeTitle.bold())
                        .foregroundColor(.primary)
                        .accessibilityAddTraits(.isHeader)
                    
                    // Signup Form
                    signupForm
                        .padding(.top, Constants.spacing)
                    
                    // Terms and Privacy
                    termsAndPrivacySection
                        .padding(.top, Constants.spacing)
                }
                .padding()
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .foregroundColor(.primary)
                            .accessibilityLabel("Close")
                    }
                }
            }
            .background(Color.background)
        }
        // Loading Overlay
        .overlay {
            if viewModel.isLoading {
                LoadingView(message: "Creating your account...")
            }
        }
        // Error Handling
        .alert("Error", isPresented: Binding(
            get: { viewModel.error != nil },
            set: { if !$0 { viewModel.error = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            if let error = viewModel.error {
                Text(error.localizedDescription)
            }
        }
    }
    
    // MARK: - Form Components
    
    private var signupForm: some View {
        VStack(spacing: Constants.spacing) {
            // Email Field
            SecureInputField(
                text: $viewModel.email,
                placeholder: "Email",
                icon: "envelope.fill",
                keyboardType: .emailAddress,
                autocapitalization: .none,
                validation: viewModel.validateEmail
            )
            .focused($focusedField, equals: .email)
            .accessibilityHint("Enter your email address")
            
            // Password Field
            SecureInputField(
                text: $viewModel.password,
                placeholder: "Password",
                icon: "lock.fill",
                isSecure: true,
                validation: viewModel.validatePassword
            )
            .focused($focusedField, equals: .password)
            .accessibilityHint("Enter a secure password with at least 8 characters")
            
            // Confirm Password Field
            SecureInputField(
                text: $viewModel.confirmPassword,
                placeholder: "Confirm Password",
                icon: "lock.fill",
                isSecure: true
            )
            .focused($focusedField, equals: .confirmPassword)
            .accessibilityHint("Confirm your password")
            
            // Biometric Option
            if viewModel.isBiometricAvailable {
                biometricToggle
            }
            
            // Signup Button
            signupButton
                .padding(.top, Constants.spacing)
        }
    }
    
    private var biometricToggle: some View {
        Toggle(isOn: .constant(true)) {
            HStack {
                Image(systemName: "faceid")
                    .foregroundColor(.primary)
                Text("Enable Face ID for future logins")
                    .foregroundColor(.primary)
            }
        }
        .toggleStyle(SwitchToggleStyle(tint: .accent))
        .accessibilityHint("Enable biometric authentication for secure login")
    }
    
    private var signupButton: some View {
        Button(action: handleSignup) {
            Text("Create Account")
                .font(.headline)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: Constants.fieldHeight)
                .background(
                    RoundedRectangle(cornerRadius: Constants.cornerRadius)
                        .fill(Color.accent)
                        .opacity(viewModel.isValid ? 1 : 0.6)
                )
        }
        .disabled(!viewModel.isValid)
        .accessibilityLabel("Create account button")
        .accessibilityHint(viewModel.isValid ? "Double tap to create your account" : "Complete all fields to enable")
    }
    
    private var termsAndPrivacySection: some View {
        VStack(spacing: 8) {
            Text("By creating an account, you agree to our")
                .foregroundColor(.secondary)
            
            HStack(spacing: 4) {
                Button("Terms of Service") {
                    // Handle terms action
                }
                Text("and")
                    .foregroundColor(.secondary)
                Button("Privacy Policy") {
                    // Handle privacy action
                }
            }
        }
        .font(.footnote)
        .multilineTextAlignment(.center)
    }
    
    // MARK: - Actions
    
    private func handleSignup() {
        withAnimation {
            viewModel.signup()
                .receive(on: DispatchQueue.main)
                .sink { completion in
                    if case .failure(let error) = completion {
                        viewModel.error = error
                    }
                } receiveValue: { _ in
                    dismiss()
                }
                .store(in: &viewModel.cancellables)
        }
    }
}

// MARK: - Supporting Types

/// Enum representing focusable form fields
private enum Field {
    case email
    case password
    case confirmPassword
}

// MARK: - Preview Provider

#if DEBUG
struct SignupView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            SignupView()
            
            SignupView()
                .preferredColorScheme(.dark)
            
            SignupView()
                .environment(\.dynamicTypeSize, .accessibility1)
        }
    }
}
#endif