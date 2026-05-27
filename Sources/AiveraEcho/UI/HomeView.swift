import SwiftUI

struct HomeView: View {

    // Repository + AudioPlayer are owned by AppDelegate and injected via .environmentObject().
    // SpeechRecognizer is local — only this screen records.
    @EnvironmentObject private var repo: ReminderRepository
    @EnvironmentObject private var audioPlayer: AudioPlayer
    @StateObject private var speech = SpeechRecognizer()
    @State private var showRecordingOverlay = false
    @State private var pendingReviewText: String?
    @State private var lastError: String?

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
                    if let reminder {
                        Task { try? await repo.add(reminder) }
                    }
                    pendingReviewText = nil
                }
            }
            .alert("Something went wrong",
                   isPresented: Binding(get: { lastError != nil }, set: { _ in lastError = nil })) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(lastError ?? "")
            }
            .onDisappear { audioPlayer.stop() }
        }
    }

    @ViewBuilder
    private var content: some View {
        if repo.reminders.isEmpty {
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
                ForEach(repo.reminders) { reminder in
                    let isThisRowPlaying =
                        audioPlayer.isPlaying &&
                        audioPlayer.nowPlayingURL?.path == reminder.audioPath
                    ReminderRow(
                        reminder: reminder,
                        isPlaying: isThisRowPlaying,
                        onToggle: { Task { try? await repo.toggleComplete(reminder) } },
                        onPlay: {
                            if isThisRowPlaying { audioPlayer.stop() }
                            else                { audioPlayer.play(path: reminder.audioPath) }
                        }
                    )
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            Task { try? await repo.delete(reminder) }
                        } label: { Label("Delete", systemImage: "trash") }
                    }
                }
            }
            .listStyle(.plain)
        }
    }

    // MARK: - Recording lifecycle

    private func micPressed() {
        if speech.isRecording {
            speech.stop()
        } else {
            Task {
                let ok = await speech.requestPermissions()
                guard ok else {
                    lastError = "Microphone and Speech Recognition permission needed in Settings."
                    return
                }
                showRecordingOverlay = true
                do {
                    try await speech.start()
                } catch {
                    lastError = error.localizedDescription
                    showRecordingOverlay = false
                }
            }
        }
    }

    private func saveFromRecording() {
        speech.stop()
        Task {
            // Brief delay so the recogniser can post the final transcript.
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
    let db  = try! AppDatabase.makeEphemeral()
    let sched = NotificationScheduler()
    return HomeView()
        .environmentObject(ReminderRepository(database: db, scheduler: sched))
        .environmentObject(AudioPlayer())
}
