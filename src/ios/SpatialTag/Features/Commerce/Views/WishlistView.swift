// SwiftUI - iOS 15.0+ - UI framework components with accessibility support
import SwiftUI
// Combine - iOS 15.0+ - Reactive programming support
import Combine

/// A highly accessible and performant view for managing user wishlists with WCAG 2.1 AA compliance
struct WishlistView: View {
    // MARK: - Properties
    
    @StateObject private var viewModel: WishlistViewModel
    @State private var isCreatingWishlist = false
    @State private var newWishlistName = ""
    @State private var selectedVisibility: WishlistVisibility = .private
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.scenePhase) private var scenePhase
    
    private let hapticFeedback = UINotificationFeedbackGenerator()
    private let logger = Logger.shared
    
    // MARK: - Constants
    
    private enum Constants {
        static let listSpacing: CGFloat = 12
        static let cellPadding: CGFloat = 16
        static let cornerRadius: CGFloat = 12
        static let maxNameLength = 50
        static let minimumNameLength = 3
        static let animationDuration = 0.3
    }
    
    // MARK: - Initialization
    
    init(viewModel: WishlistViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }
    
    // MARK: - Body
    
    var body: some View {
        NavigationView {
            ZStack {
                // Background
                Color.background
                    .edgesIgnoringSafeArea(.all)
                
                // Main content
                if viewModel.loadingState {
                    LoadingView(message: "Loading your wishlists...")
                        .accessibilityLabel("Loading wishlists")
                } else if let error = viewModel.errorState {
                    ErrorView(
                        error: error,
                        retryAction: { viewModel.retryLastOperation() }
                    )
                } else {
                    wishlistContent
                }
            }
            .navigationTitle("Wishlists")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    createButton
                }
            }
        }
        .onChange(of: scenePhase) { phase in
            handleScenePhaseChange(phase)
        }
    }
    
    // MARK: - Content Views
    
    @ViewBuilder
    private var wishlistContent: some View {
        ScrollView {
            LazyVStack(spacing: Constants.listSpacing) {
                ForEach(viewModel.wishlists) { wishlist in
                    wishlistCell(wishlist)
                        .transition(.opacity.combined(with: .move(edge: .leading)))
                }
            }
            .padding()
        }
        .refreshable {
            await viewModel.fetchWishlists()
        }
        .sheet(isPresented: $isCreatingWishlist) {
            createWishlistSheet
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Wishlist collection")
    }
    
    private func wishlistCell(_ wishlist: Wishlist) -> some View {
        HStack(spacing: Constants.listSpacing) {
            // Wishlist info
            VStack(alignment: .leading, spacing: 4) {
                Text(wishlist.name)
                    .font(.headline)
                    .foregroundColor(.primary)
                    .lineLimit(1)
                
                Text("\(wishlist.items.count) items")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Visibility badge
            visibilityBadge(wishlist.visibility)
        }
        .padding(Constants.cellPadding)
        .background(
            RoundedRectangle(cornerRadius: Constants.cornerRadius)
                .fill(Color.background)
                .shadow(radius: 2)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            handleWishlistSelection(wishlist)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            swipeActions(for: wishlist)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Wishlist: \(wishlist.name), \(wishlist.items.count) items")
        .accessibilityAddTraits(.isButton)
    }
    
    private var createWishlistSheet: some View {
        NavigationView {
            Form {
                Section {
                    TextField("Wishlist Name", text: $newWishlistName)
                        .textContentType(.name)
                        .disableAutocorrection(true)
                        .accessibilityLabel("Enter wishlist name")
                    
                    Picker("Visibility", selection: $selectedVisibility) {
                        Text("Private").tag(WishlistVisibility.private)
                        Text("Shared").tag(WishlistVisibility.shared)
                    }
                    .accessibilityLabel("Select wishlist visibility")
                }
                
                Section {
                    Button(action: handleCreateWishlist) {
                        Text("Create Wishlist")
                            .frame(maxWidth: .infinity)
                            .foregroundColor(.white)
                    }
                    .disabled(!isValidWishlistName)
                    .listRowBackground(
                        Color.blue
                            .opacity(isValidWishlistName ? 1 : 0.5)
                    )
                    .accessibilityHint(
                        isValidWishlistName ?
                        "Double tap to create wishlist" :
                        "Name must be between \(Constants.minimumNameLength) and \(Constants.maxNameLength) characters"
                    )
                }
            }
            .navigationTitle("New Wishlist")
            .navigationBarItems(
                trailing: Button("Cancel") {
                    isCreatingWishlist = false
                }
            )
        }
        .presentationDetents([.medium])
    }
    
    private var createButton: some View {
        Button(action: {
            hapticFeedback.prepare()
            isCreatingWishlist = true
        }) {
            Image(systemName: "plus.circle.fill")
                .imageScale(.large)
        }
        .accessibilityLabel("Create new wishlist")
    }
    
    // MARK: - Helper Views
    
    private func visibilityBadge(_ visibility: WishlistVisibility) -> some View {
        Text(visibility == .private ? "Private" : "Shared")
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(visibility == .private ? Color.gray : Color.blue)
                    .opacity(0.2)
            )
            .foregroundColor(visibility == .private ? .gray : .blue)
            .accessibilityLabel("Visibility: \(visibility == .private ? "Private" : "Shared")")
    }
    
    private func swipeActions(for wishlist: Wishlist) -> some View {
        Group {
            Button(role: .destructive) {
                handleWishlistDeletion(wishlist)
            } label: {
                Label("Delete", systemImage: "trash")
            }
            .accessibilityLabel("Delete wishlist")
            
            Button {
                handleWishlistSharing(wishlist)
            } label: {
                Label("Share", systemImage: "square.and.arrow.up")
            }
            .tint(.blue)
            .accessibilityLabel("Share wishlist")
        }
    }
    
    // MARK: - Helper Methods
    
    private var isValidWishlistName: Bool {
        newWishlistName.count >= Constants.minimumNameLength &&
        newWishlistName.count <= Constants.maxNameLength
    }
    
    private func handleScenePhaseChange(_ phase: ScenePhase) {
        switch phase {
        case .active:
            viewModel.onAppear()
        case .background:
            viewModel.onDisappear()
        default:
            break
        }
    }
    
    private func handleCreateWishlist() {
        guard isValidWishlistName else { return }
        
        hapticFeedback.notificationOccurred(.success)
        
        Task {
            do {
                try await viewModel.createWishlist(
                    name: newWishlistName,
                    visibility: selectedVisibility
                )
                isCreatingWishlist = false
                newWishlistName = ""
            } catch {
                logger.error("Failed to create wishlist: \(error.localizedDescription)")
            }
        }
    }
    
    private func handleWishlistSelection(_ wishlist: Wishlist) {
        hapticFeedback.selectionChanged()
        viewModel.selectedWishlist = wishlist
    }
    
    private func handleWishlistDeletion(_ wishlist: Wishlist) {
        hapticFeedback.notificationOccurred(.warning)
        
        Task {
            do {
                try await viewModel.deleteWishlist(wishlist)
            } catch {
                logger.error("Failed to delete wishlist: \(error.localizedDescription)")
            }
        }
    }
    
    private func handleWishlistSharing(_ wishlist: Wishlist) {
        hapticFeedback.notificationOccurred(.success)
        
        Task {
            do {
                try await viewModel.shareWishlist(wishlist)
            } catch {
                logger.error("Failed to share wishlist: \(error.localizedDescription)")
            }
        }
    }
}

// MARK: - Preview Provider

#if DEBUG
struct WishlistView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            // Light mode
            WishlistView(viewModel: WishlistViewModel())
            
            // Dark mode
            WishlistView(viewModel: WishlistViewModel())
                .preferredColorScheme(.dark)
            
            // Loading state
            WishlistView(viewModel: WishlistViewModel())
                .previewDisplayName("Loading State")
            
            // Error state
            WishlistView(viewModel: WishlistViewModel())
                .previewDisplayName("Error State")
            
            // Accessibility
            WishlistView(viewModel: WishlistViewModel())
                .environment(\.dynamicTypeSize, .accessibility2)
                .previewDisplayName("Accessibility")
        }
    }
}
#endif