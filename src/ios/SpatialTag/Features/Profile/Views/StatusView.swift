// SwiftUI - iOS 15.0+ - Core UI framework
import SwiftUI

/// A SwiftUI view that displays detailed user status information with support for
/// animations, accessibility, and dark mode compatibility.
struct StatusView: View {
    // MARK: - Properties
    
    @ObservedObject private var viewModel: StatusViewModel
    
    private let progressAnimation = Animation.spring(response: 0.6, dampingFraction: 0.8)
    private let achievementAnimation = Animation.easeInOut(duration: 0.3)
    
    // MARK: - Initialization
    
    init(viewModel: StatusViewModel) {
        self.viewModel = viewModel
        
        // Configure accessibility identifier for UI testing
        #if DEBUG
        _viewModel.projectedValue.accessibilityIdentifier = "StatusView"
        #endif
    }
    
    // MARK: - Body
    
    var body: some View {
        VStack(spacing: 24) {
            // Status Badge
            StatusBadgeView(status: viewModel.currentLevel)
                .accessibilityLabel("Current status: \(viewModel.currentLevel.description)")
            
            // Points Display
            Text("\(viewModel.currentPoints) Points")
                .font(.system(.title, design: .rounded))
                .fontWeight(.bold)
                .foregroundColor(.primary)
                .accessibilityLabel("Total points: \(viewModel.currentPoints)")
            
            // Progress Bar
            progressView()
                .padding(.horizontal)
            
            // Points to Next Level
            if let pointsNeeded = viewModel.pointsToNextLevel {
                Text("\(pointsNeeded) points to next level")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .accessibilityHint("Need \(pointsNeeded) more points to reach next level")
            }
            
            // Achievements Grid
            achievementsView()
                .padding(.top)
        }
        .padding()
        .background(Color(.systemBackground))
        .onAppear {
            viewModel.onAppear()
        }
        .onDisappear {
            viewModel.onDisappear()
        }
    }
    
    // MARK: - Private Views
    
    @ViewBuilder
    private func progressView() -> some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Background Track
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(.systemGray5))
                    .frame(height: 12)
                
                // Progress Bar
                RoundedRectangle(cornerRadius: 8)
                    .fill(viewModel.currentLevel.themeColor)
                    .frame(width: geometry.size.width * viewModel.progressPercentage / 100, height: 12)
                    .animation(progressAnimation, value: viewModel.progressPercentage)
            }
        }
        .frame(height: 12)
        .accessibilityValue("\(Int(viewModel.progressPercentage))% progress towards next level")
        .accessibilityAddTraits(.updatesFrequently)
    }
    
    @ViewBuilder
    private func achievementsView() -> some View {
        LazyVGrid(columns: [
            GridItem(.adaptive(minimum: 150, maximum: 200), spacing: 16)
        ], spacing: 16) {
            ForEach(viewModel.achievements) { achievement in
                achievementCard(achievement)
            }
        }
    }
    
    @ViewBuilder
    private func achievementCard(_ achievement: Achievement) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: achievement.iconName)
                    .font(.title2)
                    .foregroundColor(viewModel.currentLevel.themeColor)
                
                Spacer()
                
                if achievement.isUnlocked {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                }
            }
            
            Text(achievement.title)
                .font(.headline)
                .lineLimit(1)
            
            Text(achievement.description)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(2)
            
            if !achievement.isUnlocked {
                ProgressView(value: achievement.progress, total: 1.0)
                    .tint(viewModel.currentLevel.themeColor)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.secondarySystemBackground))
        )
        .transition(.scale.combined(with: .opacity))
        .animation(achievementAnimation, value: achievement.isUnlocked)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(achievement.title) achievement")
        .accessibilityValue(achievement.isUnlocked ? "Unlocked" : "\(Int(achievement.progress * 100))% complete")
        .accessibilityAddTraits(achievement.isUnlocked ? [.isButton, .isSelected] : [.isButton])
    }
}

// MARK: - Preview Provider

#if DEBUG
struct StatusView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            StatusView(viewModel: StatusViewModel())
                .previewDisplayName("Light Mode")
            
            StatusView(viewModel: StatusViewModel())
                .preferredColorScheme(.dark)
                .previewDisplayName("Dark Mode")
        }
    }
}
#endif