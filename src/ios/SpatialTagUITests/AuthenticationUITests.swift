//
// AuthenticationUITests.swift
// SpatialTagUITests
//
// UI test suite for authentication flows with accessibility validation
// XCTest version: iOS 15.0+
//

import XCTest

class AuthenticationUITests: XCTestCase {
    
    private var app: XCUIApplication!
    private let defaultTimeout: TimeInterval = 10.0
    
    override func setUpWithError() throws {
        // Continue running tests after failures
        continueAfterFailure = false
        
        // Initialize and configure test application
        app = XCUIApplication()
        app.launchArguments.append("--uitesting")
        app.launchEnvironment["UITEST_MODE"] = "1"
        
        // Reset authentication state
        UserDefaults.standard.removePersistentDomain(forName: Bundle.main.bundleIdentifier!)
        
        // Launch the app
        app.launch()
    }
    
    override func tearDownWithError() throws {
        // Clean up test environment
        app.terminate()
        
        // Reset biometric simulation state
        let launchArgs = ProcessInfo.processInfo.arguments
        if launchArgs.contains("--resetBiometrics") {
            // Reset biometric simulation state
        }
        
        // Clear any cached test data
        app = nil
    }
    
    func testLoginWithValidCredentials() throws {
        // Verify login screen accessibility
        let loginScreen = app.otherElements["loginScreenView"]
        XCTAssertTrue(loginScreen.exists, "Login screen should be accessible")
        
        // Test email field accessibility
        let emailField = app.textFields["emailTextField"]
        XCTAssertTrue(emailField.exists && emailField.isEnabled)
        XCTAssertEqual(emailField.value as? String, "Email")
        
        // Enter valid email
        emailField.tap()
        emailField.typeText("test@example.com")
        
        // Verify email VoiceOver reading
        XCTAssertEqual(emailField.label, "Email address text field")
        
        // Test password field accessibility
        let passwordField = app.secureTextFields["passwordTextField"]
        XCTAssertTrue(passwordField.exists && passwordField.isEnabled)
        
        // Enter valid password
        passwordField.tap()
        passwordField.typeText("ValidP@ssw0rd")
        
        // Verify password field security
        XCTAssertTrue(passwordField.isSecureTextEntry)
        
        // Test login button accessibility
        let loginButton = app.buttons["loginButton"]
        XCTAssertTrue(loginButton.exists && loginButton.isEnabled)
        XCTAssertEqual(loginButton.label, "Log in")
        
        // Attempt login
        loginButton.tap()
        
        // Verify loading indicator
        let loadingIndicator = app.activityIndicators["loadingIndicator"]
        XCTAssertTrue(loadingIndicator.exists)
        
        // Wait for main screen navigation
        let mainScreen = app.otherElements["mainScreenView"]
        XCTAssertTrue(mainScreen.waitForExistence(timeout: defaultTimeout))
        
        // Verify authentication state
        XCTAssertTrue(app.state.contains(.authenticated))
    }
    
    func testLoginWithInvalidCredentials() throws {
        // Verify form accessibility
        let loginForm = app.otherElements["loginForm"]
        XCTAssertTrue(loginForm.exists)
        
        // Test invalid email
        let emailField = app.textFields["emailTextField"]
        emailField.tap()
        emailField.typeText("invalid-email")
        
        // Verify email error accessibility
        let emailError = app.staticTexts["emailErrorLabel"]
        XCTAssertTrue(emailError.exists)
        XCTAssertEqual(emailError.label, "Invalid email format")
        
        // Test invalid password
        let passwordField = app.secureTextFields["passwordTextField"]
        passwordField.tap()
        passwordField.typeText("short")
        
        // Verify password error accessibility
        let passwordError = app.staticTexts["passwordErrorLabel"]
        XCTAssertTrue(passwordError.exists)
        XCTAssertEqual(passwordError.label, "Password must be at least 8 characters")
        
        // Attempt login with invalid credentials
        let loginButton = app.buttons["loginButton"]
        loginButton.tap()
        
        // Verify error alert accessibility
        let alert = app.alerts["loginErrorAlert"]
        XCTAssertTrue(alert.waitForExistence(timeout: defaultTimeout))
        XCTAssertEqual(alert.label, "Login Failed")
        
        // Verify error message
        let errorMessage = alert.staticTexts["errorMessage"]
        XCTAssertTrue(errorMessage.exists)
        XCTAssertEqual(errorMessage.label, "Invalid email or password")
        
        // Verify user remains on login screen
        XCTAssertTrue(app.otherElements["loginScreenView"].exists)
    }
    
    func testBiometricAuthentication() throws {
        // Verify biometric button accessibility
        let biometricButton = app.buttons["biometricAuthButton"]
        XCTAssertTrue(biometricButton.exists && biometricButton.isEnabled)
        XCTAssertEqual(biometricButton.label, "Sign in with Face ID")
        
        // Tap biometric authentication
        biometricButton.tap()
        
        // Verify biometric prompt
        let biometricPrompt = app.alerts["biometricPrompt"]
        XCTAssertTrue(biometricPrompt.waitForExistence(timeout: defaultTimeout))
        XCTAssertEqual(biometricPrompt.label, "Face ID Authentication")
        
        // Simulate successful biometric
        app.setSimulatedBiometricAuthenticationResponse(true)
        
        // Verify success feedback
        let successFeedback = app.staticTexts["authenticationSuccessMessage"]
        XCTAssertTrue(successFeedback.waitForExistence(timeout: defaultTimeout))
        
        // Verify navigation to main screen
        let mainScreen = app.otherElements["mainScreenView"]
        XCTAssertTrue(mainScreen.waitForExistence(timeout: defaultTimeout))
        
        // Test biometric fallback
        app.setSimulatedBiometricAuthenticationResponse(false)
        let fallbackButton = app.buttons["useFallbackAuthButton"]
        XCTAssertTrue(fallbackButton.exists)
        XCTAssertEqual(fallbackButton.label, "Use Password Instead")
    }
}