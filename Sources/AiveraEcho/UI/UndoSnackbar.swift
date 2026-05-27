import SwiftUI

/// Bottom-anchored snackbar with an Undo action. Auto-dismisses via a `.task`
/// timer driven by the row id, so a fresh delete resets the countdown.
struct UndoSnackbar: View {
    let message: String
    let onUndo: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            Text(message)
                .foregroundStyle(.primary)

            Spacer()

            Button(action: onUndo) {
                Text("Undo")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.tint)
            }
            .accessibilityLabel("Undo delete")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.25), radius: 12, y: 4)
        )
        .padding(.horizontal, 16)
        .padding(.bottom, 32)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}
