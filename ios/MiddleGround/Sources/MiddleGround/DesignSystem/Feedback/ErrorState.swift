import SwiftUI

struct ErrorState: View {
    let message: String
    var onRetry: (() -> Void)?
    
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 44))
                .foregroundStyle(MGColors.sunshine)
            
            Text("Something went wrong")
                .font(MGFonts.h2)
                .foregroundStyle(MGColors.slate)
            
            Text(message)
                .font(MGFonts.body)
                .foregroundStyle(MGColors.warm600)
                .multilineTextAlignment(.center)
            
            if let onRetry {
                PrimaryButton(title: "Try Again", systemImage: "arrow.clockwise") {
                    onRetry()
                }
                .padding(.top, 8)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .background(MGColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Error: \(message). \(onRetry != nil ? "Tap to try again." : "")")
    }
}

#Preview {
    ErrorState(message: "Couldn't load your requests.") {}
        .padding()
        .background(MGColors.sand)
}
