// SwiftUI - Core UI framework (iOS 15.0+)
import SwiftUI
// Combine - Reactive programming support (iOS 15.0+)
import Combine
// LocalAuthentication - Biometric authentication (iOS 15.0+)
import LocalAuthentication

/// A secure and accessible login view implementing email/password and biometric authentication
struct LoginView: View {
    // MARK: - View Model
    
    @StateObject private var viewModel: LoginViewModel
    
    // MARK: - State
    
    @State private var email = ""
    @State private var password = ""
    @State private var showPassword = false
    @State private var isEmailValid = false
    @State private var isPasswordValid = false
    @FocusState private var isEmailFocused: Bool
    @FocusState private var isPasswordFocused: Bool
    
    // MARK: - Constants
    
    private enum Constants {
        static let spacing: CGFloat = 24
        static let cornerRadius: CGFloat = 12
        static let iconSize: CGFloat = 24
        static let buttonHeight: CGFloat = 50
    }
    
    // MARK: - Initialization
    
    init(viewModel: LoginViewModel = LoginViewModel()) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }
    
    // MARK: - Body
    
    var body: some View {
        ZStack {
            // Background
            Color.background
                .ignoresSafeArea()
            
            // Main content
            ScrollView {
                VStack(spacing: Constants.spacing) {
                    // Logo and title
                    Image("app-logo")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 120, height: 120)
                        .accessibilityLabel("Spatial Tag Logo")
                    
                    Text("Welcome Back")
                        .font(.title)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                    
                    // Email field
                    VStack(alignment: .leading, spacing: 8) {
                        TextField("Email", text: $email)
                            .textContentType(.emailAddress)
                            .keyboardType(.emailAddress)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                            .focused($isEmailFocused)
                            .onChange(of: email) { _ in
                                viewModel.validateEmail(email)
                            }
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .accessibilityLabel("Email address")
                        
                        if !isEmailValid && !email.isEmpty {
                            Text("Please enter a valid email")
                                .font(.caption)
                                .foregroundColor(.red)
                                .accessibilityLabel("Email validation error")
                        }
                    }
                    
                    // Password field
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Group {
                                if showPassword {
                                    TextField("Password", text: $password)
                                } else {
                                    SecureField("Password", text: $password)
                                }
                            }
                            .textContentType(.password)
                            .focused($isPasswordFocused)
                            .onChange(of: password) { _ in
                                viewModel.validatePassword(password)
                            }
                            
                            Button(action: { showPassword.toggle() }) {
                                Image(systemName: showPassword ? "eye.slash.fill" : "eye.fill")
                                    .foregroundColor(.secondary)
                            }
                            .accessibilityLabel(showPassword ? "Hide password" : "Show password")
                        }
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        
                        if !isPasswordValid && !password.isEmpty {
                            Text("Password must be at least 12 characters")
                                .font(.caption)
                                .foregroundColor(.red)
                                .accessibilityLabel("Password validation error")
                        }
                    }
                    
                    // Login button
                    Button(action: handleLogin) {
                        if viewModel.isLoading {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        } else {
                            Text("Sign In")
                                .fontWeight(.semibold)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: Constants.buttonHeight)
                    .background(Color.primary)
                    .foregroundColor(.white)
                    .cornerRadius(Constants.cornerRadius)
                    .disabled(!isEmailValid || !isPasswordValid || viewModel.isLoading)
                    
                    // Biometric login
                    if viewModel.isBiometricAvailable {
                        Button(action: handleBiometricLogin) {
                            HStack {
                                Image(systemName: "faceid")
                                    .font(.system(size: Constants.iconSize))
                                Text("Sign in with Face ID")
                            }
                        }
                        .disabled(viewModel.isLoading)
                        .accessibilityLabel("Sign in with biometrics")
                    }
                    
                    // Forgot password
                    Button("Forgot Password?") {
                        // Handle forgot password
                    }
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.top, 8)
                }
                .padding()
                .padding(.vertical, 40)
            }
            .scrollDismissesKeyboard(.immediately)
        }
        // Loading overlay
        .loading(viewModel.isLoading)
        
        // Error handling
        .errorAlert(Binding(
            get: { viewModel.error },
            set: { _ in viewModel.error = nil }
        ))
        
        // Keyboard handling
        .onTapGesture {
            isEmailFocused = false
            isPasswordFocused = false
        }
    }
    
    // MARK: - Actions
    
    private func handleLogin() {
        guard isEmailValid && isPasswordValid else { return }
        
        // Provide haptic feedback
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        
        // Attempt login
        viewModel.login(email: email, password: password)
    }
    
    private func handleBiometricLogin() {
        // Provide haptic feedback
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        
        // Attempt biometric login
        viewModel.loginWithBiometrics()
    }
}

// MARK: - Preview Provider

#if DEBUG
struct LoginView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            LoginView()
            
            LoginView()
                .preferredColorScheme(.dark)
            
            LoginView()
                .environment(\.dynamicTypeSize, .accessibility1)
        }
    }
}
#endif