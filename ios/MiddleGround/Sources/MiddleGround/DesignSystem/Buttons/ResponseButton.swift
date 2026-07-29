import SwiftUI

struct ResponseButton: View {
    let type: ResponseType
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Text(type.emoji)
                    .font(.system(size: 22))
                Text(type.displayName)
                    .font(MGFonts.caption)
                    .foregroundStyle(type.color)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(type.color.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(type.color.opacity(0.2), lineWidth: 1)
            )
        }
        .buttonStyle(ScaleButtonStyle())
        .accessibilityLabel("\(type.displayName) request")
        .accessibilityHint("Double tap to \(type.displayName.lowercased()) this request")
    }
}

#Preview {
    HStack(spacing: 12) {
        ResponseButton(type: .accept) {}
        ResponseButton(type: .negotiate) {}
        ResponseButton(type: .decline) {}
    }
    .padding()
    .background(MGColors.sand)
}
