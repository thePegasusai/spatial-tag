//
// ProductDetailView.swift
// SpatialTag
//
// Enhanced SwiftUI view for secure product details display with
// accessibility and performance optimizations
//

import SwiftUI

/// A secure and accessible product detail view with enhanced commerce functionality
struct ProductDetailView: View {
    // MARK: - Properties
    
    @StateObject private var viewModel: ProductDetailViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    
    private let imageAspectRatio: CGFloat = 1.33
    private let cornerRadius: CGFloat = 12
    private let shadowRadius: CGFloat = 4
    
    // MARK: - Initialization
    
    init(viewModel: ProductDetailViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }
    
    // MARK: - Body
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Secure product image loading
                productImageSection
                
                // Product details with security measures
                productDetailsSection
                
                // Secure price display
                priceSection
                
                // Action buttons
                actionButtonsSection
            }
            .padding()
        }
        .adaptiveBackground()
        .navigationBarTitleDisplayMode(.inline)
        .loading(viewModel.isLoading)
        .errorAlert(Binding(
            get: { viewModel.error },
            set: { _ in viewModel.clearError() }
        ))
        .onAppear {
            viewModel.onAppear()
        }
        .onDisappear {
            viewModel.onDisappear()
        }
    }
    
    // MARK: - View Components
    
    private var productImageSection: some View {
        Group {
            if let imageUrl = viewModel.product.imageUrl {
                AsyncImage(url: imageUrl) { phase in
                    switch phase {
                    case .empty:
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .aspectRatio(imageAspectRatio, contentMode: .fit)
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
                            .shadow(radius: shadowRadius)
                    case .failure:
                        Image(systemName: "photo")
                            .font(.largeTitle)
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity)
                            .aspectRatio(imageAspectRatio, contentMode: .fit)
                    @unknown default:
                        EmptyView()
                    }
                }
                .accessibilityLabel("Product image: \(viewModel.product.name)")
            }
        }
        .secureImageLoading()
    }
    
    private var productDetailsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(viewModel.product.name)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.primary)
                .dynamicTypeSize(...DynamicTypeSize.accessibility2)
                .accessibilityAddTraits(.isHeader)
            
            Text(viewModel.product.description)
                .font(.body)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        }
        .accessibilityElement(children: .combine)
    }
    
    private var priceSection: some View {
        HStack {
            Text(formatSecurePrice(viewModel.product.encryptedPrice, 
                                 currency: viewModel.product.currency))
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundColor(.primary)
            
            Spacer()
            
            if viewModel.isInWishlist {
                Image(systemName: "heart.fill")
                    .foregroundColor(.red)
                    .accessibilityLabel("Added to wishlist")
            }
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
    }
    
    private var actionButtonsSection: some View {
        VStack(spacing: 12) {
            Button(action: {
                Task {
                    await viewModel.toggleWishlistStatus()
                }
            }) {
                HStack {
                    Image(systemName: viewModel.isInWishlist ? "heart.fill" : "heart")
                    Text(viewModel.isInWishlist ? "Remove from Wishlist" : "Add to Wishlist")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.accentColor)
                .foregroundColor(.white)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            }
            .disabled(viewModel.isLoading)
            .accessibilityHint(viewModel.isInWishlist ? 
                             "Double tap to remove from wishlist" : 
                             "Double tap to add to wishlist")
            
            Button(action: {
                Task {
                    await viewModel.initiatePayment()
                }
            }) {
                Text("Buy Now")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.primary)
                    .foregroundColor(colorScheme == .dark ? .black : .white)
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            }
            .disabled(viewModel.isLoading)
            .accessibilityHint("Double tap to proceed to payment")
        }
    }
    
    // MARK: - Helper Methods
    
    private func formatSecurePrice(_ encryptedPrice: Data, currency: String) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency
        
        do {
            let decryptedPrice = try viewModel.decryptPrice(encryptedPrice)
            return formatter.string(from: NSNumber(value: decryptedPrice)) ?? "Invalid Price"
        } catch {
            return "Price Unavailable"
        }
    }
}

// MARK: - Preview Provider

#if DEBUG
struct ProductDetailView_Previews: PreviewProvider {
    static var previews: some View {
        let mockProduct = try! WishlistItem(
            id: UUID(),
            name: "Sample Product",
            description: "A high-quality sample product for testing",
            price: 99.99,
            currency: "USD"
        )
        
        let viewModel = ProductDetailViewModel(
            product: mockProduct,
            commerceService: CommerceService()
        )
        
        Group {
            NavigationView {
                ProductDetailView(viewModel: viewModel)
            }
            
            NavigationView {
                ProductDetailView(viewModel: viewModel)
                    .preferredColorScheme(.dark)
            }
            
            NavigationView {
                ProductDetailView(viewModel: viewModel)
                    .environment(\.dynamicTypeSize, .accessibility1)
            }
        }
    }
}
#endif