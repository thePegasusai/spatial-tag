//
// TagCreationUITests.swift
// SpatialTagUITests
//
// UI test suite for tag creation functionality
// XCTest version: Latest
//

import XCTest

class TagCreationUITests: XCTestCase {
    
    private var app: XCUIApplication!
    private let defaultTimeout: TimeInterval = 30.0
    private var isARSessionActive: Bool = false
    
    // MARK: - Test Lifecycle
    
    override func setUp() {
        super.setUp()
        
        // Initialize application
        app = XCUIApplication()
        app.launchArguments.append("--uitesting")
        
        // Configure test metrics
        continueAfterFailure = false
        XCTMetric.applicationLaunchMetric.map { measure(metrics: [$0]) }
        
        // Verify device capabilities
        let deviceRequirements = verifyDeviceCapabilities()
        XCTAssertTrue(deviceRequirements.hasLiDAR, "Device must have LiDAR capability")
        XCTAssertTrue(deviceRequirements.hasARKit, "Device must support ARKit")
        
        app.launch()
        
        // Navigate to tag creation
        let createTagButton = app.buttons["createTagButton"]
        XCTAssertTrue(createTagButton.waitForExistence(timeout: defaultTimeout))
        createTagButton.tap()
    }
    
    override func tearDown() {
        // Collect performance metrics
        if isARSessionActive {
            captureARMetrics()
        }
        
        // Clean up test artifacts
        cleanupTestData()
        
        app.terminate()
        super.tearDown()
    }
    
    // MARK: - Test Cases
    
    func testTagCreationFormValidation() {
        // Test title input validation
        let titleField = app.textFields["tagTitleInput"]
        XCTAssertTrue(titleField.exists)
        
        // Empty title validation
        app.buttons["createButton"].tap()
        XCTAssertTrue(app.staticTexts["titleErrorMessage"].exists)
        
        // Title length validation
        let longTitle = String(repeating: "a", count: 51)
        titleField.tap()
        titleField.typeText(longTitle)
        XCTAssertTrue(app.staticTexts["titleLengthError"].exists)
        
        // Valid title
        titleField.tap()
        titleField.clearText()
        titleField.typeText("Test Tag")
        XCTAssertFalse(app.staticTexts["titleErrorMessage"].exists)
        
        // Description validation
        let descriptionField = app.textViews["tagDescriptionInput"]
        XCTAssertTrue(descriptionField.exists)
        
        // Description length validation
        let longDescription = String(repeating: "a", count: 201)
        descriptionField.tap()
        descriptionField.typeText(longDescription)
        XCTAssertTrue(app.staticTexts["descriptionLengthError"].exists)
        
        // Verify accessibility
        XCTAssertTrue(verifyAccessibility(element: titleField))
        XCTAssertTrue(verifyAccessibility(element: descriptionField))
    }
    
    func testARPlacementMode() {
        // Initialize AR session
        let arView = app.otherElements["arPlacementView"]
        XCTAssertTrue(arView.waitForExistence(timeout: defaultTimeout))
        isARSessionActive = true
        
        // Test surface detection
        let surfaceDetectedPredicate = NSPredicate(format: "exists == true")
        let surfaceIndicator = app.otherElements["surfaceDetectionIndicator"]
        expectation(for: surfaceDetectedPredicate, evaluatedWith: surfaceIndicator)
        waitForExpectations(timeout: defaultTimeout)
        
        // Test placement gesture
        let placementPoint = arView.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        placementPoint.tap()
        
        // Verify preview
        XCTAssertTrue(app.images["tagPreview"].exists)
        
        // Test distance validation
        let distanceIndicator = app.staticTexts["distanceWarning"]
        XCTAssertFalse(distanceIndicator.exists, "Tag should be within valid distance range")
        
        // Confirm placement
        app.buttons["confirmPlacement"].tap()
        XCTAssertTrue(app.buttons["createButton"].isEnabled)
        
        // Measure AR performance
        measureARMetrics()
    }
    
    func testTagCreationEndToEnd() {
        // Fill form with valid data
        let titleField = app.textFields["tagTitleInput"]
        titleField.tap()
        titleField.typeText("Coffee Meetup")
        
        let descriptionField = app.textViews["tagDescriptionInput"]
        descriptionField.tap()
        descriptionField.typeText("Let's meet for coffee!")
        
        // Set visibility
        let visibilitySlider = app.sliders["visibilityRadiusSlider"]
        visibilitySlider.adjust(toNormalizedSliderPosition: 0.5)
        
        // Set duration
        let durationPicker = app.pickers["durationPicker"]
        durationPicker.adjust(toPickerWheelValue: "4 Hours")
        
        // Place tag in AR
        let arView = app.otherElements["arPlacementView"]
        let placementPoint = arView.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        placementPoint.tap()
        app.buttons["confirmPlacement"].tap()
        
        // Create tag
        let createButton = app.buttons["createButton"]
        XCTAssertTrue(createButton.isEnabled)
        createButton.tap()
        
        // Verify success
        let successMessage = app.staticTexts["successMessage"]
        XCTAssertTrue(successMessage.waitForExistence(timeout: defaultTimeout))
    }
    
    // MARK: - Helper Methods
    
    private func verifyDeviceCapabilities() -> (hasLiDAR: Bool, hasARKit: Bool) {
        let deviceInfo = ProcessInfo.processInfo.environment
        return (
            hasLiDAR: deviceInfo["DEVICE_HAS_LIDAR"] == "1",
            hasARKit: deviceInfo["DEVICE_HAS_ARKIT"] == "1"
        )
    }
    
    private func verifyAccessibility(element: XCUIElement) -> Bool {
        let isAccessibilityElement = element.isAccessibilityElement
        let hasAccessibilityLabel = !element.label.isEmpty
        let hasAccessibilityHint = !element.hint.isEmpty
        
        // Test dynamic type
        let metrics = XCTOSSignpostMetric.applicationMetrics()
        measure(metrics: metrics) {
            element.adjust(forContentSizeCategory: .accessibilityExtraExtraExtraLarge)
        }
        
        return isAccessibilityElement && hasAccessibilityLabel && hasAccessibilityHint
    }
    
    private func measureARMetrics() {
        let metrics: [XCTMetric] = [
            XCTCPUMetric(),
            XCTMemoryMetric(),
            XCTStorageMetric(),
            XCTClockMetric()
        ]
        
        measure(metrics: metrics) {
            // Perform AR session operations
            let arView = app.otherElements["arPlacementView"]
            let placementPoint = arView.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            placementPoint.tap()
            sleep(2)
        }
    }
    
    private func captureARMetrics() {
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.lifetime = .keepAlways
        add(attachment)
    }
    
    private func cleanupTestData() {
        // Remove test artifacts
        let fileManager = FileManager.default
        let testArtifactsURL = fileManager.temporaryDirectory.appendingPathComponent("TestArtifacts")
        try? fileManager.removeItem(at: testArtifactsURL)
    }
}

// MARK: - XCUIElement Extensions

extension XCUIElement {
    func clearText() {
        guard let stringValue = self.value as? String else { return }
        let deleteString = String(repeating: XCUIKeyboardKey.delete.rawValue, count: stringValue.count)
        typeText(deleteString)
    }
}