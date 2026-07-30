import SwiftUI

struct RequestTypePicker: View {
    @Binding var selected: RequestCategory

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 90))], spacing: 12) {
            ForEach(RequestCategory.allCases) { category in
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                        selected = category
                    }
                    Haptics.shared.impact(.light)
                } label: {
                    VStack(spacing: 8) {
                        Image(systemName: category.iconName)
                            .font(.system(size: 24, weight: .semibold))
                        Text(category.displayName)
                            .mgFont(.caption)
                    }
                    .foregroundStyle(selected == category ? MGColors.onAccent : MGColors.slate)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(selected == category ? MGColors.indigo : MGColors.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .shadow(color: MGColors.slate.opacity(0.05), radius: 8, x: 0, y: 2)
                }
                .buttonStyle(ScaleButtonStyle())
            }
        }
    }
}

#Preview {
    @Previewable @State var category: RequestCategory = .relationship
    RequestTypePicker(selected: $category)
        .padding()
        .background(MGColors.sand)
}
