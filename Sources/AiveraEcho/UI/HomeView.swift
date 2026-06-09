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

    /// Reminder whose custom snooze date is being chosen (drives the sheet).
    @State private var snoozingReminder: Reminder?
    @State private var customSnoozeDate: Date = Date().addingTimeInterval(60 * 60)
    @State private var showAccount = false
    @State private var showSettings = false

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
                    Button(action: { showAccount = true }) {
                        Image(systemName: "person.crop.circle")
                    }
                    .accessibilityLabel("Account & sync")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: { showSettings = true }) {
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
            // Undo snackbar — auto-dismisses after 5 seconds of no further deletes.
            .overlay(alignment: .bottom) {
                if let deleted = repo.recentlyDeleted {
                    UndoSnackbar(
                        message: "Reminder deleted",
                        onUndo: { Task { await repo.undoDelete() } }
                    )
                    .id(deleted.id)
                    .task(id: deleted.id) {
                        try? await Task.sleep(nanoseconds: 5_000_000_000)
                        if !Task.isCancelled { repo.clearUndo() }
                    }
                    .animation(.spring(duration: 0.3), value: deleted.id)
                }
            }
            // Custom snooze date picker — Material-style sheet at .medium height.
            .sheet(item: $snoozingReminder) { reminder in
                NavigationStack {
                    Form {
                        DatePicker(
                            "Snooze until",
                            selection: $customSnoozeDate,
                            in: Date().addingTimeInterval(60)...,
                            displayedComponents: [.date, .hourAndMinute]
                        )
                        .datePickerStyle(.graphical)
                    }
                    .navigationTitle("Custom snooze")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("Cancel") { snoozingReminder = nil }
                        }
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Snooze") {
                                Task {
                                    var copy = reminder
                                    copy.triggerAt = customSnoozeDate
                                    copy.completed = false
                                    copy.completedAt = nil
                                    try? await repo.update(copy)
                                    snoozingReminder = nil
                                }
                            }
                            .bold()
                        }
                    }
                }
                .presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $showAccount) {
                AccountSheet()
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if repo.homeStats.isEmpty {
            // FR-HOME-014 — pulsing brand orb + warm copy.
            EnhancedEmptyState()
        } else {
            // FR-HOME-001 to 013 + FR-HOME-006/007/008/009 — Daily Hero at
            // top, optional Stats Strip, then time-grouped reminder sections.
            List {
                Section {
                    DailyHeroHeader(stats: repo.homeStats)
                        .listRowInsets(EdgeInsets())
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                    if repo.homeStats.showStatsStrip {
                        StatsStrip(stats: repo.homeStats)
                            .listRowInsets(EdgeInsets())
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                    }
                }

                ForEach(TimeBucket.displayOrder, id: \.self) { bucket in
                    let items = repo.homeStats.buckets[bucket] ?? []
                    if !items.isEmpty {
                        // Recently Done is the only collapsible bucket on
                        // Android. SwiftUI's `Section` is always-expanded by
                        // default — adding collapse state is a polish task
                        // for M5.4b. For v1 we always render it expanded,
                        // matching the rest of the buckets.
                        Section(header: SectionHeaderRow(bucket: bucket, count: items.count)) {
                            ForEach(items) { reminder in
                                rowFor(reminder)
                            }
                        }
                    }
                }
            }
            .listStyle(.plain)
        }
    }

    @ViewBuilder
    private func rowFor(_ reminder: Reminder) -> some View {
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
            },
            onSnooze: { minutes in
                Task { try? await repo.snooze(reminder, minutes: minutes) }
            },
            onSnoozeCustom: {
                customSnoozeDate = max(reminder.triggerAt, Date().addingTimeInterval(60))
                snoozingReminder = reminder
            }
        )
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                Task { try? await repo.delete(reminder) }
            } label: { Label("Delete", systemImage: "trash") }
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
            let raw = (speech.finalText.isEmpty ? speech.partialText : speech.finalText)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            showRecordingOverlay = false

            // FR-AI-001 — try the cloud smart parser for non-trivial inputs.
            // Heuristic matches Android: anything compound or longer than a
            // quick phrase. Short phrases skip the network round-trip and go
            // straight to the review sheet.
            let looksCompound = raw.range(of: " and ", options: .caseInsensitive) != nil ||
                raw.range(of: " then ", options: .caseInsensitive) != nil ||
                raw.range(of: " also ", options: .caseInsensitive) != nil
            let shouldTrySmart = !raw.isEmpty && (looksCompound || raw.count > 30)

            if shouldTrySmart {
                let parsed = await SmartParser.parse(raw)
                if parsed.count > 1 {
                    // Compound utterance → silent batch-save, no review sheet.
                    // Audio is attached to the FIRST reminder only (the
                    // original voice memo); subsequent ones reuse the same
                    // triggerAt by default.
                    for (index, p) in parsed.enumerated() {
                        let reminder = Reminder(
                            text: p.text,
                            triggerAt: p.triggerAt,
                            audioPath: index == 0 ? speech.lastAudioURL?.path : nil,
                            recurrence: p.recurrence,
                            triggerType: .time,
                            dirty: true
                        )
                        try? await repo.add(reminder)
                    }
                    return
                }
                if let only = parsed.first {
                    // Single AI parse → drop into review sheet pre-filled.
                    // Override pendingReviewText with the cleaned text so
                    // the review row matches what Claude extracted.
                    pendingReviewText = only.text
                    return
                }
                // Empty parse → fall through to the original raw-text path.
            }

            pendingReviewText = raw.isEmpty ? "Reminder" : raw
        }
    }

    private func cancelRecording() {
        speech.cancel()
        showRecordingOverlay = false
    }
}

#Preview {
    let db       = try! AppDatabase.makeEphemeral()
    let sched    = NotificationScheduler()
    let repo     = ReminderRepository(database: db, scheduler: sched)
    let session  = SessionStore()
    let settings = SettingsStore()
    return HomeView()
        .environmentObject(repo)
        .environmentObject(AudioPlayer())
        .environmentObject(LocationManager())
        .environmentObject(session)
        .environmentObject(SyncEngine(database: db, repository: repo, sessionStore: session, settingsStore: settings))
        .environmentObject(EntitlementStore(sessionStore: session))
        .environmentObject(settings)
}
