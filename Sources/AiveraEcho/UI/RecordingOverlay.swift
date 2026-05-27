import SwiftUI

struct RecordingOverlay: View {
    @ObservedObject var speech: SpeechRecognizer
    let onSave: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Text("Listening…")
                .font(.title.weight(.medium))
                .foregroundStyle(Color.echoAccent)

            // Simple amplitude bar — replace with a real waveform in a later iteration.
            GeometryReader { geo in
                Capsule()
                    .fill(Color.echoAccent.opacity(0.2))
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(LinearGradient(colors: [.echoGlow, .echoAccent],
                                                 startPoint: .leading, endPoint: .trailing))
                            .frame(width: geo.size.width * CGFloat(speech.amplitude))
                            .animation(.easeOut(duration: 0.05), value: speech.amplitude)
                    }
            }
            .frame(height: 6)
            .padding(.horizontal, 48)

            Text(displayText)
                .font(.title3)
                .multilineTextAlignment(.center)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, minHeight: 120, alignment: .center)
                .padding(.horizontal, 24)

            Spacer()

            HStack(spacing: 40) {
                Button(action: onCancel) {
                    Image(systemName: "xmark")
                        .font(.title2)
                        .foregroundStyle(.white)
                        .frame(width: 64, height: 64)
                        .background(Color.secondary.opacity(0.3))
                        .clipShape(Circle())
                }
                .accessibilityLabel("Cancel")

                Button(action: onSave) {
                    Image(systemName: "checkmark")
                        .font(.title)
                        .foregroundStyle(.white)
                        .frame(width: 88, height: 88)
                        .background(
                            LinearGradient(colors: [.echoAccent, .echoPurple],
                                           startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                        .clipShape(Circle())
                        .shadow(color: .echoAccent.opacity(0.5), radius: 16)
                }
                .accessibilityLabel("Save")
            }
            .padding(.bottom, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.echoBg.ignoresSafeArea())
        .preferredColorScheme(.dark)
    }

    private var displayText: String {
        if !speech.partialText.isEmpty { return speech.partialText }
        if !speech.finalText.isEmpty   { return speech.finalText }
        if let err = speech.errorMessage { return err }
        return "Speak your reminder, then tap the check."
    }
}
