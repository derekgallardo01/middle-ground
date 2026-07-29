import SwiftUI

struct RequestCard: View {
    let request: Request
    let onRespond: ((ResponseType) -> Void)?
    
    @State private var showActions = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: request.category.iconName)
                    .foregroundStyle(MGColors.indigo)
                    .font(.system(size: 14, weight: .semibold))
                
                Spacer()
                
                StatusBadge(status: request.status)
            }
            
            Text(request.title)
                .font(MGFonts.h3)
                .foregroundStyle(MGColors.slate)
            
            if let details = request.details, !details.isEmpty {
                Text(details)
                    .font(MGFonts.bodySmall)
                    .foregroundStyle(MGColors.warm600)
                    .lineLimit(2)
            }
            
            if let time = request.proposedTime {
                HStack(spacing: 4) {
                    Image(systemName: "clock")
                        .font(.system(size: 12))
                    Text(time, style: .date)
                        .font(MGFonts.caption)
                }
                .foregroundStyle(MGColors.warm600)
            }
            
            if request.isPending && onRespond != nil {
                HStack(spacing: 8) {
                    ResponseButton(type: .accept) {
                        onRespond?(.accept)
                        Haptics.shared.notification(.success)
                    }
                    ResponseButton(type: .negotiate) {
                        onRespond?(.negotiate)
                        Haptics.shared.impact(.light)
                    }
                    ResponseButton(type: .decline) {
                        onRespond?(.decline)
                        Haptics.shared.notification(.error)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .bottom)))
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Response options")
            }
        }
        .padding(16)
        .background(MGColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: MGColors.slate.opacity(0.06), radius: 12, x: 0, y: 4)
    }
}

struct StatusBadge: View {
    let status: RequestStatus
    
    var body: some View {
        Text(status.displayName)
            .font(MGFonts.caption)
            .fontWeight(.bold)
            .foregroundStyle(status.color)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(status.color.opacity(0.12))
            .clipShape(Capsule())
            .accessibilityLabel("Status: \(status.displayName)")
    }
}

#Preview {
    VStack(spacing: 16) {
        RequestCard(request: .preview) { _ in }
        RequestCard(request: .previewNegotiating, onRespond: nil)
    }
    .padding()
    .background(MGColors.sand)
}
