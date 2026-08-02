import SwiftUI

/// The Middle Ground brand mark: two figures — one indigo, one teal — meeting at a coral heart.
///
/// From `brand/design-system.md`: *"Two people coming together around a shared heart… It
/// represents empathy, compromise, and connection."* Until now the app showed a lone SF
/// `heart.fill` in its place, which dropped the half of the metaphor that carries the meaning.
///
/// Drawn with Shapes rather than shipped as a bitmap so it stays crisp at any size, follows
/// the adaptive brand palette in light and dark, and adds nothing to the bundle.
struct LogoMark: View {
    /// Geometry is expressed in the 512×512 space of `brand/logo-mark.svg` and scaled to fit.
    private enum Spec {
        static let canvas: CGFloat = 512
        static let headRadius: CGFloat = 48
        static let bodyWidth: CGFloat = 160
        static let bodyHeight: CGFloat = 280
        static let leftHeadCenter = CGPoint(x: 170, y: 130)
        static let rightHeadCenter = CGPoint(x: 342, y: 130)
        static let leftBodyOrigin = CGPoint(x: 95, y: 190)
        static let rightBodyOrigin = CGPoint(x: 257, y: 190)
    }

    var body: some View {
        GeometryReader { geo in
            let scale = min(geo.size.width, geo.size.height) / Spec.canvas

            ZStack {
                figure(headCenter: Spec.leftHeadCenter, bodyOrigin: Spec.leftBodyOrigin, scale: scale)
                    .foregroundStyle(MGColors.indigo)

                figure(headCenter: Spec.rightHeadCenter, bodyOrigin: Spec.rightBodyOrigin, scale: scale)
                    .foregroundStyle(MGColors.teal)

                HeartShape()
                    .fill(MGColors.coral)
                    .frame(width: 132 * scale, height: 170 * scale)
                    .offset(y: 20 * scale)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }

    private func figure(headCenter: CGPoint, bodyOrigin: CGPoint, scale: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            Circle()
                .frame(width: Spec.headRadius * 2 * scale, height: Spec.headRadius * 2 * scale)
                .offset(
                    x: (headCenter.x - Spec.headRadius) * scale,
                    y: (headCenter.y - Spec.headRadius) * scale
                )

            Capsule()
                .frame(width: Spec.bodyWidth * scale, height: Spec.bodyHeight * scale)
                .offset(x: bodyOrigin.x * scale, y: bodyOrigin.y * scale)
        }
        .frame(width: Spec.canvas * scale, height: Spec.canvas * scale, alignment: .topLeading)
    }
}

/// The heart from the brand mark, as a resolution-independent path.
private struct HeartShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let width = rect.width
        let height = rect.height

        path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addCurve(
            to: CGPoint(x: rect.minX, y: rect.minY + height * 0.29),
            control1: CGPoint(x: rect.minX + width * 0.08, y: rect.maxY - height * 0.24),
            control2: CGPoint(x: rect.minX, y: rect.minY + height * 0.62)
        )
        path.addCurve(
            to: CGPoint(x: rect.midX, y: rect.minY + height * 0.24),
            control1: CGPoint(x: rect.minX, y: rect.minY - height * 0.06),
            control2: CGPoint(x: rect.minX + width * 0.30, y: rect.minY - height * 0.15)
        )
        path.addCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY + height * 0.29),
            control1: CGPoint(x: rect.maxX - width * 0.30, y: rect.minY - height * 0.15),
            control2: CGPoint(x: rect.maxX, y: rect.minY - height * 0.06)
        )
        path.addCurve(
            to: CGPoint(x: rect.midX, y: rect.maxY),
            control1: CGPoint(x: rect.maxX, y: rect.minY + height * 0.62),
            control2: CGPoint(x: rect.maxX - width * 0.08, y: rect.maxY - height * 0.24)
        )
        path.closeSubpath()
        return path
    }
}

#Preview("Light") {
    LogoMark()
        .frame(width: 200, height: 200)
        .padding(40)
        .background(MGColors.sand)
}

#Preview("Dark") {
    LogoMark()
        .frame(width: 200, height: 200)
        .padding(40)
        .background(MGColors.sand)
        .preferredColorScheme(.dark)
}
