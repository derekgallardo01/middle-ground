import SwiftUI

struct RequestTypePicker: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var selected: RequestCategory

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 90))], spacing: 12) {
            ForEach(RequestCategory.allCases) { category in
                Button {
                    withAnimation(reduceMotion ? nil : MGMotion.tap) {
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
                    .clipShape(RoundedRectangle(cornerRadius: MGRadius.md, style: .continuous))
                    .mgShadow(MGShadow.sm)
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
