// SwiftUI - iOS 15.0+ - Core UI framework
import SwiftUI
// Combine - iOS 15.0+ - Reactive programming support
import Combine

/// A SwiftUI view that displays detailed information about a spatial tag with enhanced
/// accessibility support, animations, and error handling capabilities.
struct TagDetailView: View {
    // MARK: - Properties
    
    @StateObject private var viewModel: TagDetailViewModel
    @Environment(\.presentationMode) private var presentationMode
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.sizeCategory) private var sizeCategory
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    
    @State private var showDeleteConfirmation = false
    @State private var showRetryAlert = false
    @State private var contentOpacity: Double = 0
    @State private var isContentExpanded = false
    
    private let animationDuration: Double = 0.3
    private let hapticFeedback = UIImpactFeedbackGenerator(style: .medium)
    
    // MARK: - Initialization
    
    init(tag: Tag) {
        _viewModel = StateObject(wrappedValue: TagDetailViewModel(tag: tag))
    }
    
    // MARK: - Body
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Tag Content Section
                tagContentSection
                    .opacity(contentOpacity)
                    .animation(.easeIn(duration: animationDuration), value: contentOpacity)
                
                // Location Section
                locationSection
                    .opacity(contentOpacity)
                    .animation(.easeIn(duration: animationDuration).delay(0.1), value: contentOpacity)
                
                // Creator Section
                creatorSection
                    .opacity(contentOpacity)
                    .animation(.easeIn(duration: animationDuration).delay(0.2), value: contentOpacity)
                
                // Expiration Section
                expirationSection
                    .opacity(contentOpacity)
                    .animation(.easeIn(duration: animationDuration).delay(0.3), value: contentOpacity)
                
                // Action Buttons
                actionButtons
                    .opacity(contentOpacity)
                    .animation(.easeIn(duration: animationDuration).delay(0.4), value: contentOpacity)
            }
            .padding()
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if viewModel.isOwner {
                    deleteButton
                }
            }
        }
        .overlay {
            if viewModel.isLoading {
                loadingOverlay
            }
        }
        .alert("Error", isPresented: .constant(viewModel.error != nil)) {
            Button("Retry") {
                viewModel.retryLastOperation()
            }
            Button("Cancel", role: .cancel) {
                viewModel.error = nil
            }
        } message: {
            if let error = viewModel.error {
                Text(error.localizedDescription)
            }
        }
        .confirmationDialog("Delete Tag?",
                          isPresented: $showDeleteConfirmation,
                          titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                handleDelete()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This action cannot be undone.")
        }
        .onAppear {
            viewModel.onAppear()
            withAnimation {
                contentOpacity = 1
            }
        }
        .onDisappear {
            viewModel.onDisappear()
        }
    }
    
    // MARK: - Content Sections
    
    private var tagContentSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(viewModel.tag.content)
                .font(.body)
                .lineLimit(isContentExpanded ? nil : 3)
                .onTapGesture {
                    withAnimation(.spring()) {
                        isContentExpanded.toggle()
                        hapticFeedback.impactOccurred()
                    }
                }
                .accessibilityLabel("Tag content")
                .accessibilityAddTraits(.startsMediaSession)
                .accessibilityHint("Double tap to expand or collapse content")
            
            HStack {
                Text("Created \(viewModel.tag.createdAt.formatted())")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Text("\(viewModel.interactionCount) interactions")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(UIColor.secondarySystemBackground))
        )
    }
    
    private var locationSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Location", systemImage: "location.fill")
                .font(.headline)
            
            Text(formatLocation(viewModel.tag.location))
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(UIColor.secondarySystemBackground))
        )
        .accessibilityElement(children: .combine)
    }
    
    private var creatorSection: some View {
        HStack {
            VStack(alignment: .leading) {
                Text("Created by")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                Text("@username") // Would be populated from actual user data
                    .font(.headline)
            }
            
            Spacer()
            
            StatusBadgeView(status: .elite) // Would use actual creator's status
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(UIColor.secondarySystemBackground))
        )
    }
    
    private var expirationSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Expires in", systemImage: "timer")
                .font(.headline)
            
            Text(formatTimeRemaining())
                .font(.subheadline)
                .foregroundColor(getExpirationColor())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(UIColor.secondarySystemBackground))
        )
        .accessibilityElement(children: .combine)
    }
    
    private var actionButtons: some View {
        VStack(spacing: 12) {
            if viewModel.canInteract {
                Button {
                    hapticFeedback.impactOccurred()
                    // Handle interaction
                } label: {
                    Label("Interact", systemImage: "hand.wave.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.accentColor)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }
                .disabled(!viewModel.canInteract)
            }
            
            if viewModel.isWithinRange {
                Button {
                    hapticFeedback.impactOccurred()
                    // Handle sharing
                } label: {
                    Label("Share", systemImage: "square.and.arrow.up")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color(UIColor.secondarySystemBackground))
                        .foregroundColor(.primary)
                        .cornerRadius(12)
                }
            }
        }
    }
    
    private var deleteButton: some View {
        Button(role: .destructive) {
            showDeleteConfirmation = true
        } label: {
            Image(systemName: "trash")
                .foregroundColor(.red)
        }
        .disabled(viewModel.isLoading)
    }
    
    private var loadingOverlay: some View {
        Color.black.opacity(0.3)
            .ignoresSafeArea()
            .overlay(
                ProgressView()
                    .scaleEffect(1.5)
                    .tint(.white)
            )
            .allowsHitTesting(true)
    }
    
    // MARK: - Helper Methods
    
    private func handleDelete() {
        viewModel.deleteTag()
            .receive(on: DispatchQueue.main)
            .sink { completion in
                switch completion {
                case .finished:
                    presentationMode.wrappedValue.dismiss()
                case .failure(let error):
                    viewModel.error = error
                }
            } receiveValue: { _ in }
            .store(in: &viewModel.cancellables)
    }
    
    private func formatLocation(_ location: Location) -> String {
        // Would implement actual location formatting
        return "Within \(Int(location.coordinate.latitude))m"
    }
    
    private func formatTimeRemaining() -> String {
        // Would implement actual time remaining calculation
        return "24 hours"
    }
    
    private func getExpirationColor() -> Color {
        if viewModel.tag.isExpired() {
            return .red
        }
        return .secondary
    }
}

#if DEBUG
struct TagDetailView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            TagDetailView(tag: try! Tag(
                creatorId: UUID(),
                location: try! Location(
                    coordinate: CLLocationCoordinate2D(latitude: 0, longitude: 0),
                    altitude: 0
                ),
                content: "Preview tag content"
            ))
        }
        .preferredColorScheme(.dark)
    }
}
#endif