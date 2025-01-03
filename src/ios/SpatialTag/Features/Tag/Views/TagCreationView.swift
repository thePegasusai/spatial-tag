// SwiftUI - iOS 15.0+ - Core UI framework
import SwiftUI
// Combine - iOS 15.0+ - Async operations
import Combine

/// A comprehensive tag creation interface with AR-based placement, content input,
/// visibility controls, and expiration settings with enhanced validation and accessibility
struct TagCreationView: View {
    // MARK: - View Model
    
    @StateObject private var viewModel = TagCreationViewModel()
    @StateObject private var sceneManager = ARSceneManager()
    
    // MARK: - State
    
    @State private var content: String = ""
    @State private var visibilityRadius: Double = MIN_VISIBILITY_RADIUS
    @State private var expirationHours: Int = MIN_EXPIRATION_HOURS
    @State private var isARViewActive: Bool = false
    @State private var showError: Bool = false
    @State private var errorMessage: String = ""
    
    // MARK: - Constants
    
    private let contentPlaceholder = "What's on your mind?"
    private let radiusRange: ClosedRange<Double> = MIN_VISIBILITY_RADIUS...MAX_VISIBILITY_RADIUS
    private let expirationRange: ClosedRange<Int> = MIN_EXPIRATION_HOURS...MAX_EXPIRATION_HOURS
    
    // MARK: - Body
    
    var body: some View {
        NavigationView {
            ZStack {
                // Main content
                VStack(spacing: 20) {
                    if isARViewActive {
                        // AR placement view
                        ARPlacementView(sceneManager: sceneManager)
                            .frame(maxWidth: .infinity, maxHeight: 300)
                            .cornerRadius(12)
                            .shadow(radius: 4)
                            .accessibilityElement(children: .contain)
                            .accessibilityLabel("AR Tag Placement View")
                            .accessibilityHint("Use gestures to position your tag in space")
                    }
                    
                    // Tag content input
                    createTagContent()
                    
                    // Visibility controls
                    createVisibilityControls()
                    
                    // Expiration controls
                    createExpirationControls()
                    
                    Spacer()
                    
                    // Create button
                    Button(action: createTag) {
                        if viewModel.isLoading {
                            LoadingView(message: "Creating tag...")
                        } else {
                            Text("Create Tag")
                                .font(.headline)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.accent)
                                .cornerRadius(10)
                        }
                    }
                    .disabled(!viewModel.isValid || viewModel.isLoading)
                    .accessibilityLabel("Create Tag Button")
                    .accessibilityHint("Double tap to create your tag")
                }
                .padding()
                .background(Color.background)
            }
            .navigationTitle("Create Tag")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        // Handle dismissal
                    }
                }
            }
        }
        .alert("Error", isPresented: $showError) {
            Button("OK") {
                showError = false
            }
        } message: {
            Text(errorMessage)
        }
        .onAppear {
            setupScene()
        }
        .onDisappear {
            cleanupScene()
        }
    }
    
    // MARK: - Content Views
    
    @ViewBuilder
    private func createTagContent() -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Content")
                .font(.headline)
                .foregroundColor(.primary)
            
            TextEditor(text: $content)
                .frame(height: 100)
                .padding(8)
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.primary.opacity(0.2), lineWidth: 1)
                )
                .accessibilityLabel("Tag Content Input")
                .accessibilityHint("Enter your tag message here")
            
            // Character count
            Text("\(MAX_CONTENT_LENGTH - content.count) characters remaining")
                .font(.caption)
                .foregroundColor(content.count > MAX_CONTENT_LENGTH ? .red : .secondary)
                .accessibilityLabel("Character Count")
        }
    }
    
    @ViewBuilder
    private func createVisibilityControls() -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Visibility Radius")
                .font(.headline)
                .foregroundColor(.primary)
            
            HStack {
                Slider(
                    value: $visibilityRadius,
                    in: radiusRange,
                    step: 1.0
                )
                .accessibilityLabel("Visibility Radius Slider")
                .accessibilityValue("\(Int(visibilityRadius)) meters")
                
                Text("\(Int(visibilityRadius))m")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .frame(width: 50)
            }
        }
    }
    
    @ViewBuilder
    private func createExpirationControls() -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Expiration Time")
                .font(.headline)
                .foregroundColor(.primary)
            
            Picker("Expiration Hours", selection: $expirationHours) {
                ForEach(expirationRange, id: \.self) { hours in
                    Text("\(hours) hours")
                        .tag(hours)
                }
            }
            .pickerStyle(.wheel)
            .frame(height: 100)
            .accessibilityLabel("Expiration Time Picker")
            .accessibilityValue("\(expirationHours) hours")
        }
    }
    
    // MARK: - Actions
    
    private func createTag() {
        guard viewModel.validateContent(content) else {
            showError = true
            errorMessage = "Please enter valid content"
            return
        }
        
        guard viewModel.validateVisibilityRadius(visibilityRadius) else {
            showError = true
            errorMessage = "Invalid visibility radius"
            return
        }
        
        viewModel.createTag(
            content: content,
            visibilityRadius: visibilityRadius,
            expirationHours: Double(expirationHours)
        )
        .receive(on: DispatchQueue.main)
        .sink { completion in
            switch completion {
            case .failure(let error):
                handleARSceneError(error)
            case .finished:
                break
            }
        } receiveValue: { success in
            if success {
                // Handle successful creation
            }
        }
        .store(in: &viewModel.cancellables)
    }
    
    private func setupScene() {
        sceneManager.startScene()
            .receive(on: DispatchQueue.main)
            .sink { completion in
                if case .failure(let error) = completion {
                    handleARSceneError(error)
                }
            } receiveValue: { _ in
                isARViewActive = true
            }
            .store(in: &viewModel.cancellables)
    }
    
    private func cleanupScene() {
        sceneManager.stopScene()
        viewModel.cancellables.removeAll()
    }
    
    private func handleARSceneError(_ error: Error) {
        showError = true
        errorMessage = error.localizedDescription
    }
}

// MARK: - Preview Provider

#if DEBUG
struct TagCreationView_Previews: PreviewProvider {
    static var previews: some View {
        TagCreationView()
    }
}
#endif