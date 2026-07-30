import SwiftUI

struct CelebrationView: View {
    let title: String
    let subtitle: String
    let onComplete: () -> Void

    @State private var particles: [Particle] = []
    @State private var showContent = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.3)
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
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .shadow(color: MGColors.slate.opacity(0.2), radius: 30, x: 0, y: 12)
            .scaleEffect(showContent ? 1.0 : 0.8)
            .opacity(showContent ? 1.0 : 0.0)
            .onAppear {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) {
                    showContent = true
                }
                spawnParticles()
            }

            ForEach(particles) { particle in
                Circle()
                    .fill(particle.color)
                    .frame(width: particle.size, height: particle.size)
                    .position(particle.position)
                    .opacity(particle.opacity)
                    .animation(.easeOut(duration: 1.2), value: particle.position)
                    .animation(.easeOut(duration: 1.2), value: particle.opacity)
            }
        }
    }

    private func spawnParticles() {
        let colors: [Color] = [MGColors.indigo, MGColors.teal, MGColors.coral, MGColors.sunshine, MGColors.lavender]
        for index in 0..<30 {
            let particle = Particle(
                position: CGPoint(x: 200, y: 300),
                target: CGPoint(
                    x: CGFloat.random(in: 50...350),
                    y: CGFloat.random(in: 100...500)
                ),
                color: colors[index % colors.count],
                size: CGFloat.random(in: 6...12),
                opacity: 1.0
            )
            particles.append(particle)

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                if let index = particles.firstIndex(where: { $0.id == particle.id }) {
                    withAnimation {
                        particles[index].position = particle.target
                        particles[index].opacity = 0
                    }
                }
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
