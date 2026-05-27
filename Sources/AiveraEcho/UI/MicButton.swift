import SwiftUI

struct MicButton: View {
    let isRecording: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.echoAccent, .echoPurple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 72, height: 72)
                    .shadow(color: .echoAccent.opacity(0.35), radius: 12, x: 0, y: 6)

                Image(systemName: isRecording ? "stop.fill" : "mic.fill")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(.white)
            }
        }
        .accessibilityLabel(isRecording ? "Stop recording" : "Record a reminder")
        .accessibilityHint("Double tap to \(isRecording ? "stop" : "start") recording")
        .buttonStyle(.plain)
    }
}

#Preview {
    VStack(spacing: 32) {
        MicButton(isRecording: false, action: {})
        MicButton(isRecording: true, action: {})
    }
    .padding()
    .background(Color.echoBg)
}
