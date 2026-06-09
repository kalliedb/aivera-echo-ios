import SwiftUI

/// FR-HOME-014. Replaces the old "No reminders yet" placeholder with the
/// brand orb (procedurally drawn — matches the icon-generator's gradient)
/// pulsing gently, a warm headline, sub-line, and a down-pointing arrow
/// aimed at the mic FAB.
struct EnhancedEmptyState: View {
    @State private var pulse = false

    var body: some View {
        VStack(spacing: 24) {
            Orb()
                .frame(width: 160, height: 160)
                .scaleEffect(pulse ? 1.04 : 0.96)
                .animation(
                    .easeInOut(duration: 1.8).repeatForever(autoreverses: true),
                    value: pulse
                )
                .onAppear { pulse = true }

            VStack(spacing: 8) {
                Text("Your day is wide open.")
                    .font(.title3.weight(.semibold))
                Text("Hold the orb below to capture your first reminder.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Image(systemName: "arrow.down")
                .font(.title3)
                .foregroundStyle(Color.echoAccent.opacity(0.7))
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "Your day is wide open. Hold the orb at the bottom of the screen to capture your first reminder."
        )
    }
}

/// Procedurally-drawn brand orb. Matches the gradient stops in
/// `aivera-echo-web/brand/echo-orb.svg` so the same visual identity
/// appears on the empty Home screen as the website + app icon source.
private struct Orb: View {
    var body: some View {
        Canvas { context, size in
            let radius = min(size.width, size.height) / 2
            let centre = CGPoint(x: size.width / 2, y: size.height / 2)
            let highlight = CGPoint(x: size.width * 0.38, y: size.height * 0.32)

            let gradient = Gradient(stops: [
                .init(color: Color(red: 0.957, green: 0.910, blue: 1.000), location: 0.00),
                .init(color: Color(red: 0.851, green: 0.722, blue: 1.000), location: 0.12),
                .init(color: Color(red: 0.659, green: 0.333, blue: 0.969), location: 0.35),
                .init(color: Color(red: 0.427, green: 0.157, blue: 0.851), location: 0.65),
                .init(color: Color(red: 0.180, green: 0.039, blue: 0.361), location: 1.00),
            ])

            let circle = Path(ellipseIn: CGRect(
                x: centre.x - radius,
                y: centre.y - radius,
                width: radius * 2,
                height: radius * 2
            ))
            context.fill(
                circle,
                with: .radialGradient(
                    gradient,
                    center: highlight,
                    startRadius: 0,
                    endRadius: radius * 1.3
                )
            )

            // Tiny white highlight at the light-source point.
            let core = Path(ellipseIn: CGRect(
                x: highlight.x - radius * 0.07,
                y: highlight.y - radius * 0.07,
                width: radius * 0.14,
                height: radius * 0.14
            ))
            context.fill(core, with: .color(.white.opacity(0.9)))
        }
    }
}
