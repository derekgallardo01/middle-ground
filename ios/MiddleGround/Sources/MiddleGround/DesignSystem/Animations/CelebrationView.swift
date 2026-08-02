import SwiftUI

struct CelebrationView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let title: String
    let subtitle: String
    let onComplete: () -> Void

    @State private var particles: [Particle] = []
    @State private var showContent = false

    var body: some View {
      GeometryReader { geo in
        ZStack {
            MGColors.shadow.opacity(0.35)  // adaptive: a black scrim is invisible over dark sand
                .ignoresSafeArea()
                .onTapGesture { onComplete() }

            VStack(spacing: 16) {
                Text("🎉")
                    .font(.system(size: 64))

                Text(title)
                    .mgFont(.h1)
                    .foregroundStyle(MGColors.indigo)

                if !subtitle.isEmpty {
                    Text(subtitle)
                        .mgFont(.body)
                        .foregroundStyle(MGColors.warm600)
                        .multilineTextAlignment(.center)
                }

                PrimaryButton(title: "Awesome", systemImage: nil) {
                    onComplete()
                }
                .padding(.top, 8)
            }
            .padding(28)
            .background(MGColors.surface)
            .mgCard(radius: MGRadius.xl)
            .mgShadow(MGShadow.lg)
            .scaleEffect(showContent ? 1.0 : 0.8)
            .opacity(showContent ? 1.0 : 0.0)
            .onAppear {
                if reduceMotion {
                    showContent = true
                } else {
                    withAnimation(MGMotion.celebrate) { showContent = true }
                }
            }

            ForEach(particles) { particle in
                Circle()
                    .fill(particle.color)
                    .frame(width: particle.size, height: particle.size)
                    .position(particle.position)
                    .opacity(particle.opacity)
                    // Not an MGMotion token: confetti is a physical simulation, not interface
                    // motion, and wants a linear-out fall rather than a spring. Unguarded is
                    // safe here because `spawnParticles` returns early under Reduce Motion, so
                    // there is nothing to animate.
                    .animation(.easeOut(duration: 1.2), value: particle.position)
                    .animation(.easeOut(duration: 1.2), value: particle.opacity)
            }
        }
        .frame(width: geo.size.width, height: geo.size.height)
        .onAppear { spawnParticles(in: geo.size) }
      }
      .ignoresSafeArea()
    }

    /// Bursts confetti radially from the centre of the actual view.
    ///
    /// The origin used to be a hardcoded `CGPoint(x: 200, y: 300)`, which is left-of-centre on
    /// any modern iPhone and a small cluster in the corner on iPad. Every particle also fired
    /// on the same deadline, so there was no stagger.
    private func spawnParticles(in size: CGSize) {
        guard !reduceMotion else { return }

        let colors: [Color] = [MGColors.indigo, MGColors.teal, MGColors.coral, MGColors.sunshine, MGColors.lavender]
        let origin = CGPoint(x: size.width / 2, y: size.height / 2)
        let spread = min(size.width, size.height) * 0.45

        for index in 0..<30 {
            // Angle and distance are both Double, and the conversion to CGFloat happens once, at
            // the end. Mixing them — a Double angle times a CGFloat distance — compiles on Xcode
            // 26.6 and fails on 26.3 with "Ambiguous use of 'cos'", because the implicit
            // CGFloat/Double bridging leaves the compiler a choice of overloads. CI runs the
            // older toolchain, so a local build is the more permissive of the two, not the
            // stricter one.
            let angle = (Double(index) / 30.0) * 2 * .pi + Double.random(in: -0.2...0.2)
            let distance = Double(spread) * Double.random(in: 0.5...1.0)
            let particle = Particle(
                position: origin,
                target: CGPoint(
                    x: origin.x + CGFloat(cos(angle) * distance),
                    y: origin.y + CGFloat(sin(angle) * distance)
                ),
                color: colors[index % colors.count],
                size: CGFloat.random(in: 6...12),
                opacity: 1.0
            )
            particles.append(particle)

            // Stagger so the burst reads as motion rather than a single jump.
            let delay = Double(index) * 0.012
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                guard let idx = particles.firstIndex(where: { $0.id == particle.id }) else { return }
                particles[idx].position = particle.target
                particles[idx].opacity = 0
            }
        }
    }
}

private struct Particle: Identifiable {
    let id = UUID()
    var position: CGPoint
    var target: CGPoint
    let color: Color
    let size: CGFloat
    var opacity: Double
}

#Preview {
    CelebrationView(title: "You found Middle Ground!", subtitle: "Great job working together.") {}
}
