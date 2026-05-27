import SwiftUI

struct ReviewDraft: Identifiable {
    let id = UUID()
    var text: String
    var audioURL: URL?
}

struct ReviewSheet: View {
    @State var draft: ReviewDraft
    let onClose: (Reminder?) -> Void

    @State private var triggerAt: Date = Date().addingTimeInterval(60 * 60)
    @State private var recurrence: Recurrence = .none

    var body: some View {
        NavigationStack {
            Form {
                Section("Reminder") {
                    TextField("What should I remind you about?",
                              text: $draft.text, axis: .vertical)
                        .lineLimit(3...6)
                }
                Section("When") {
                    DatePicker("Time", selection: $triggerAt, displayedComponents: [.date, .hourAndMinute])
                    Picker("Repeats", selection: $recurrence) {
                        ForEach(Recurrence.allCases, id: \.self) { r in
                            Text(r.label).tag(r)
                        }
                    }
                }
                if draft.audioURL != nil {
                    Section("Voice clip") {
                        // TODO: AVPlayer playback control in a later iteration.
                        Label("Audio attached", systemImage: "waveform")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("New reminder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { onClose(nil) }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        let reminder = Reminder(
                            text: draft.text.trimmingCharacters(in: .whitespacesAndNewlines),
                            triggerAt: triggerAt,
                            audioPath: draft.audioURL?.path,
                            recurrence: recurrence
                        )
                        onClose(reminder)
                    }
                    .bold()
                }
            }
        }
    }
}
