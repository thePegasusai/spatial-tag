// SwiftUI - iOS 15.0+ - Core UI framework
import SwiftUI

/// A SwiftUI view that displays and manages user profile information with enhanced accessibility
/// and performance optimizations for the SpatialTag application.
struct ProfileView: View {
    // MARK: - Properties
    
    @StateObject private var viewModel: ProfileViewModel
    @State private var isEditMode = false
    @State private var showingImagePicker = false
    @State private var isAnimating = false
    @Environment(\.sizeCategory) private var sizeCategory
    @Environment(\.colorScheme) private var colorScheme
    
    // MARK: - Constants
    
    private let animationDuration: Double = 0.3
    private let progressBarHeight: CGFloat = 8
    private let imageSize: CGFloat = 120
    
    // MARK: - Initialization
    
    init(viewModel: ProfileViewModel = ProfileViewModel()) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }
    
    // MARK: - Body
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    profileHeader
                    progressSection
                    statisticsSection
                }
                .padding()
                .animation(.easeInOut(duration: animationDuration), value: isAnimating)
            }
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(isEditMode ? "Done" : "Edit") {
                        withAnimation {
                            isEditMode.toggle()
                        }
                    }
                }
            }
            .overlay {
                if viewModel.isLoading {
                    LoadingView(message: "Updating profile...")
                }
            }
            .alert("Error", isPresented: .constant(viewModel.error != nil)) {
                Button("Retry") {
                    viewModel.retryLastOperation()
                }
                Button("OK") {
                    viewModel.error = nil
                }
            } message: {
                if let error = viewModel.error {
                    Text(error.localizedDescription)
                }
            }
        }
        .onAppear {
            isAnimating = true
            viewModel.onAppear()
        }
        .onDisappear {
            viewModel.onDisappear()
        }
    }
    
    // MARK: - Profile Header
    
    private var profileHeader: some View {
        VStack(spacing: 16) {
            // Profile Image
            ZStack {
                Circle()
                    .fill(Color.secondary.opacity(0.1))
                    .frame(width: imageSize, height: imageSize)
                
                if let profile = viewModel.profile {
                    AsyncImage(url: profile.imageURL) { image in
                        image
                            .resizable()
                            .scaledToFill()
                    } placeholder: {
                        Image(systemName: "person.circle.fill")
                            .resizable()
                            .foregroundColor(.secondary)
                    }
                    .frame(width: imageSize - 4, height: imageSize - 4)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Color.primary.opacity(0.1), lineWidth: 2))
                }
                
                if isEditMode {
                    Button {
                        showingImagePicker = true
                    } label: {
                        Image(systemName: "camera.circle.fill")
                            .font(.title)
                            .foregroundColor(.white)
                            .padding(8)
                            .background(Color.primary.opacity(0.7))
                            .clipShape(Circle())
                    }
                    .offset(x: imageSize/3, y: imageSize/3)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Profile picture")
            .accessibilityAddTraits(.isImage)
            
            // User Info
            VStack(spacing: 8) {
                if let profile = viewModel.profile {
                    Text(profile.displayName)
                        .font(.title2.weight(.semibold))
                        .multilineTextAlignment(.center)
                        .minimumScaleFactor(0.8)
                    
                    StatusBadgeView(
                        status: profile.statusLevel,
                        size: 28,
                        showAnimation: isAnimating
                    )
                }
            }
        }
        .padding(.vertical)
    }
    
    // MARK: - Progress Section
    
    private var progressSection: some View {
        VStack(spacing: 12) {
            // Progress Bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: progressBarHeight / 2)
                        .fill(Color.secondary.opacity(0.2))
                        .frame(height: progressBarHeight)
                    
                    RoundedRectangle(cornerRadius: progressBarHeight / 2)
                        .fill(Color.accent)
                        .frame(
                            width: geometry.size.width * viewModel.progressToNextLevel,
                            height: progressBarHeight
                        )
                        .animation(.spring(), value: viewModel.progressToNextLevel)
                }
            }
            .frame(height: progressBarHeight)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Progress to next level")
            .accessibilityValue("\(Int(viewModel.progressToNextLevel * 100))%")
            
            // Points Info
            if let pointsToNext = viewModel.pointsToNextLevel {
                Text("\(pointsToNext) points to next level")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical)
    }
    
    // MARK: - Statistics Section
    
    private var statisticsSection: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ],
            spacing: 16
        ) {
            if let profile = viewModel.profile {
                StatisticCell(
                    title: "Tags Created",
                    value: "\(profile.tagsCreated)",
                    icon: "tag.fill"
                )
                
                StatisticCell(
                    title: "Connections",
                    value: "\(profile.connections)",
                    icon: "person.2.fill"
                )
                
                StatisticCell(
                    title: "Achievements",
                    value: "\(profile.achievements)",
                    icon: "star.fill"
                )
                
                StatisticCell(
                    title: "Interaction Score",
                    value: "\(profile.interactionScore)",
                    icon: "chart.bar.fill"
                )
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Profile statistics")
    }
}

// MARK: - Supporting Views

private struct StatisticCell: View {
    let title: String
    let value: String
    let icon: String
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.accent)
            
            Text(value)
                .font(.title3.weight(.semibold))
            
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.secondary.opacity(0.1))
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(value)")
    }
}

#if DEBUG
struct ProfileView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            ProfileView()
            
            ProfileView()
                .preferredColorScheme(.dark)
            
            ProfileView()
                .environment(\.sizeCategory, .accessibilityLarge)
        }
    }
}
#endif