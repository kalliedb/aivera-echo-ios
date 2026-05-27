import SwiftUI

struct HomeView: View {
    @StateObject private var store = ReminderStore()
    @StateObject private var speech = SpeechRecognizer()
    @State private var showRecordingOverlay = false
    @State private var pendingReviewText: String?

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                content

                MicButton(isRecording: speech.isRecording) {
                    micPressed()
                }
                .padding(.bottom, 32)
            }
            .navigationTitle("Aivera Echo")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: { /* TODO: settings */ }) {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Settings")
                }
            }
            .sheet(isPresented: $showRecordingOverlay) {
                RecordingOverlay(speech: speech, onSave: saveFromRecording, onCancel: cancelRecording)
            }
            .sheet(item: Binding(
                get: { pendingReviewText.map { ReviewDraft(text: $0, audioURL: speech.lastAudioURL) } },
                set: { pendingReviewText = $0?.text }
            )) { draft in
                ReviewSheet(draft: draft) { reminder in
                    if let reminder { store.add(reminder) }
                    pendingReviewText = nil
                }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if store.reminders.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "mic.slash")
                    .font(.system(size: 48))
                    .foregroundStyle(.tertiary)
                Text("No reminders yet")
                    .font(.title3.weight(.semibold))
                Text("Hold the mic and speak — Echo turns your voice into a reminder.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 48)
            }
            .padding(.bottom, 100)
        } else {
            List {
                ForEach(store.reminders) { reminder in
                    ReminderRow(
                        reminder: reminder,
                        onToggle: { store.toggleComplete(reminder) },
                        onPlay: { /* TODO: AVPlayer */ }
                    )
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            store.delete(reminder)
                        } label: { Label("Delete", systemImage: "trash") }
                    }
                }
            }
            .listStyle(.plain)
        }
    }

    private func micPressed() {
        if speech.isRecording {
            speech.stop()
        } else {
            Task {
                let ok = await speech.requestPermissions()
                guard ok else {
                    // TODO: surface permission-denied UX
                    return
                }
                showRecordingOverlay = true
                try? await speech.start()
            }
        }
    }

    private func saveFromRecording() {
        speech.stop()
        // Once stop() lets the recognizer finalise, hand the text off to review.
        Task {
            // Brief delay to let finalText settle. SF can post final after stop().
            try? await Task.sleep(nanoseconds: 800_000_000)
            let text = speech.finalText.isEmpty ? speech.partialText : speech.finalText
            showRecordingOverlay = false
            pendingReviewText = text.isEmpty ? "Reminder" : text
        }
    }

    private func cancelRecording() {
        speech.cancel()
        showRecordingOverlay = false
    }
}

#Preview {
    HomeView()
}
