//
// EditProfileView.swift
// SpatialTag
//
// A SwiftUI view for editing user profile information with enhanced validation,
// status level integration, and comprehensive accessibility support
// Version: 1.0.0
// SwiftUI Version: iOS 15.0+
//

import SwiftUI // iOS 15.0+ - Core UI framework components
import PhotosUI // iOS 15.0+ - Photo picker functionality

/// A view that provides a user-friendly interface for editing profile information
/// with real-time validation and status level integration
@MainActor
struct EditProfileView: View {
    // MARK: - Properties
    
    @StateObject private var viewModel: EditProfileViewModel
    @State private var isImagePickerPresented = false
    @State private var hasUnsavedChanges = false
    @State private var showUnsavedChangesAlert = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    
    // MARK: - Constants
    
    private enum Constants {
        static let imageSize: CGFloat = 120
        static let spacing: CGFloat = 20
        static let cornerRadius: CGFloat = 12
        static let maxImageSizeBytes = 5 * 1024 * 1024 // 5MB
    }
    
    // MARK: - Initialization
    
    init(viewModel: EditProfileViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }
    
    // MARK: - Body
    
    var body: some View {
        NavigationView {
            ZStack {
                Color.background
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: Constants.spacing) {
                        // Status section
                        statusSection
                            .padding(.top)
                        
                        // Profile image section
                        profileImageSection
                        
                        // Profile information form
                        VStack(alignment: .leading, spacing: Constants.spacing) {
                            // Username field
                            TextField("Username", text: $viewModel.username)
                                .textFieldStyle(.roundedBorder)
                                .autocapitalization(.none)
                                .disableAutocorrection(true)
                                .accessibilityLabel("Username")
                                .overlay(
                                    RoundedRectangle(cornerRadius: Constants.cornerRadius)
                                        .stroke(
                                            validationColor,
                                            lineWidth: 1
                                        )
                                        .opacity(0.5)
                                )
                            
                            // Visibility toggle
                            Toggle("Profile Visibility", isOn: $viewModel.isVisible)
                                .tint(Color.getStatusColor(for: viewModel.statusLevel))
                                .accessibilityHint("Toggle profile visibility to others")
                            
                            // Validation message
                            if case .invalid(let error) = viewModel.validationState {
                                Text(error.localizedDescription)
                                    .font(.caption)
                                    .foregroundColor(.red)
                                    .accessibilityLabel("Validation error")
                            }
                        }
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: Constants.cornerRadius)
                                .fill(Color.background)
                                .shadow(radius: 4)
                        )
                    }
                    .padding()
                }
                
                // Loading overlay
                if viewModel.isLoading {
                    LoadingView(message: "Saving profile...")
                }
                
                // Error view
                if let error = viewModel.error {
                    ErrorView(
                        error: error,
                        retryAction: saveChanges,
                        errorColor: Color.getStatusColor(for: viewModel.statusLevel)
                    )
                }
            }
            .navigationTitle("Edit Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        if hasUnsavedChanges {
                            showUnsavedChangesAlert = true
                        } else {
                            dismiss()
                        }
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveChanges()
                    }
                    .disabled(!hasUnsavedChanges || viewModel.validationState != .valid)
                }
            }
        }
        .sheet(isPresented: $isImagePickerPresented) {
            ImagePicker(image: $viewModel.profileImage)
                .accessibilityLabel("Profile image picker")
        }
        .alert("Unsaved Changes", isPresented: $showUnsavedChangesAlert) {
            Button("Discard", role: .destructive) {
                dismiss()
            }
            Button("Keep Editing", role: .cancel) {}
        } message: {
            Text("You have unsaved changes. Are you sure you want to discard them?")
        }
        .onChange(of: viewModel.username) { _ in
            hasUnsavedChanges = true
        }
        .onChange(of: viewModel.isVisible) { _ in
            hasUnsavedChanges = true
        }
        .onChange(of: viewModel.profileImage) { _ in
            hasUnsavedChanges = true
        }
    }
    
    // MARK: - Subviews
    
    private var statusSection: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: viewModel.statusLevel.iconName)
                    .font(.title2)
                    .foregroundColor(Color.getStatusColor(for: viewModel.statusLevel))
                
                Text(viewModel.statusLevel.description)
                    .font(.headline)
                    .foregroundColor(Color.getStatusColor(for: viewModel.statusLevel))
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Status level: \(viewModel.statusLevel.description)")
            
            if !viewModel.statusLevel.isMaxLevel {
                ProgressView(value: viewModel.nextLevelProgress)
                    .tint(Color.getStatusColor(for: viewModel.statusLevel))
                    .accessibilityValue("\(Int(viewModel.nextLevelProgress * 100))% progress to next level")
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: Constants.cornerRadius)
                .fill(Color.background)
                .shadow(radius: 4)
        )
    }
    
    private var profileImageSection: some View {
        VStack {
            if let image = viewModel.profileImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: Constants.imageSize, height: Constants.imageSize)
                    .clipShape(Circle())
                    .overlay(
                        Circle()
                            .stroke(
                                Color.getStatusColor(for: viewModel.statusLevel),
                                lineWidth: 2
                            )
                    )
            } else {
                Circle()
                    .fill(Color.secondary.opacity(0.2))
                    .frame(width: Constants.imageSize, height: Constants.imageSize)
                    .overlay(
                        Image(systemName: "person.circle.fill")
                            .resizable()
                            .padding(32)
                            .foregroundColor(.secondary)
                    )
            }
            
            Button {
                isImagePickerPresented = true
            } label: {
                Text("Change Photo")
                    .font(.subheadline)
                    .foregroundColor(Color.getStatusColor(for: viewModel.statusLevel))
            }
            .accessibilityHint("Double tap to select a new profile photo")
        }
    }
    
    // MARK: - Helper Methods
    
    private var validationColor: Color {
        switch viewModel.validationState {
        case .valid:
            return .green
        case .invalid:
            return .red
        default:
            return .secondary
        }
    }
    
    private func saveChanges() {
        Task {
            do {
                try await viewModel.saveProfile()
                hasUnsavedChanges = false
                dismiss()
            } catch {
                // Error handling is managed by the view model
                // and displayed through the ErrorView
            }
        }
    }
}

// MARK: - ImagePicker

private struct ImagePicker: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    
    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.selectionLimit = 1
        config.filter = .images
        
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }
    
    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: ImagePicker
        
        init(_ parent: ImagePicker) {
            self.parent = parent
        }
        
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)
            
            guard let provider = results.first?.itemProvider else { return }
            
            if provider.canLoadObject(ofClass: UIImage.self) {
                provider.loadObject(ofClass: UIImage.self) { [weak self] image, error in
                    DispatchQueue.main.async {
                        if let image = image as? UIImage {
                            // Compress image if needed
                            let compressedImage = self?.compressImage(image)
                            self?.parent.image = compressedImage
                        }
                    }
                }
            }
        }
        
        private func compressImage(_ image: UIImage) -> UIImage {
            let maxSize = CGFloat(Constants.maxImageSizeBytes)
            var compression: CGFloat = 1.0
            var imageData = image.jpegData(compressionQuality: compression)
            
            while let data = imageData, data.count > Int(maxSize) && compression > 0.1 {
                compression -= 0.1
                imageData = image.jpegData(compressionQuality: compression)
            }
            
            if let data = imageData, let compressedImage = UIImage(data: data) {
                return compressedImage
            }
            
            return image
        }
    }
}

// MARK: - Preview Provider

#if DEBUG
struct EditProfileView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            // Regular status preview
            EditProfileView(viewModel: EditProfileViewModel(
                profile: Profile(id: UUID(), displayName: "User"),
                securityContext: SecurityContext()
            ))
            
            // Elite status preview
            EditProfileView(viewModel: EditProfileViewModel(
                profile: Profile(id: UUID(), displayName: "Elite User"),
                securityContext: SecurityContext()
            ))
            .preferredColorScheme(.dark)
            
            // Accessibility preview
            EditProfileView(viewModel: EditProfileViewModel(
                profile: Profile(id: UUID(), displayName: "Accessible User"),
                securityContext: SecurityContext()
            ))
            .environment(\.accessibilityEnabled, true)
            .environment(\.dynamicTypeSize, .accessibility1)
        }
    }
}
#endif