import CoreLocation
import SwiftUI

struct ReviewDraft: Identifiable {
    let id = UUID()
    var text: String
    var audioURL: URL?
}

struct ReviewSheet: View {
    /// If non-nil, the sheet is editing this existing reminder; on Save the
    /// callback returns a Reminder with the same id+clientId and updated
    /// fields. If nil, the sheet creates a brand-new reminder from `draft`.
    let editing: Reminder?
    @State var draft: ReviewDraft
    let onClose: (Reminder?) -> Void

    @EnvironmentObject private var locationManager: LocationManager

    // Time trigger
    @State private var triggerAt: Date
    @State private var recurrence: Recurrence

    // Trigger type picker
    @State private var triggerType: TriggerType

    // Place trigger
    @State private var latitude: Double?
    @State private var longitude: Double?
    @State private var placeLabel: String?
    @State private var radius: Double
    @State private var isLocating = false
    @State private var locationError: String?

    init(
        draft: ReviewDraft,
        editing: Reminder? = nil,
        prefilledTriggerAt: Date? = nil,
        onClose: @escaping (Reminder?) -> Void
    ) {
        self._draft = State(initialValue: draft)
        self.editing = editing
        self.onClose = onClose
        // Prefill state from the existing reminder when editing, otherwise
        // use the quick-add prefill if present, otherwise default to one
        // hour from now.
        let defaultTrigger = prefilledTriggerAt ?? Date().addingTimeInterval(60 * 60)
        self._triggerAt   = State(initialValue: editing?.triggerAt ?? defaultTrigger)
        self._recurrence  = State(initialValue: editing?.recurrence ?? .none)
        self._triggerType = State(initialValue: editing?.triggerType ?? .time)
        self._latitude    = State(initialValue: editing?.latitude)
        self._longitude   = State(initialValue: editing?.longitude)
        self._placeLabel  = State(initialValue: editing?.placeLabel)
        self._radius      = State(initialValue: editing?.radiusMeters ?? 200)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Reminder") {
                    TextField("What should I remind you about?",
                              text: $draft.text, axis: .vertical)
                        .lineLimit(3...6)
                }

                Section("Trigger") {
                    Picker("Type", selection: $triggerType) {
                        Text("Time").tag(TriggerType.time)
                        Text("Place").tag(TriggerType.location)
                    }
                    .pickerStyle(.segmented)
                }

                if triggerType == .time {
                    Section("When") {
                        DatePicker("Time", selection: $triggerAt,
                                   displayedComponents: [.date, .hourAndMinute])
                        Picker("Repeats", selection: $recurrence) {
                            ForEach(Recurrence.allCases, id: \.self) { r in
                                Text(r.label).tag(r)
                            }
                        }
                    }
                } else {
                    Section("Where") {
                        if let placeLabel {
                            Label(placeLabel, systemImage: "mappin.circle.fill")
                                .foregroundStyle(Color.echoAccent)
                        }

                        Button(action: useCurrentLocation) {
                            HStack {
                                if isLocating {
                                    ProgressView().controlSize(.small)
                                } else {
                                    Image(systemName: "location.fill")
                                }
                                Text(isLocating ? "Getting your location…"
                                                : (latitude == nil ? "Use current location"
                                                                   : "Update location"))
                            }
                        }
                        .disabled(isLocating)

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Radius: \(Int(radius)) m")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Slider(value: $radius, in: 50...1000, step: 50)
                                .accessibilityLabel("Radius in metres")
                        }
                    }
                    if let locationError {
                        Section { Text(locationError).foregroundStyle(.red) }
                    }
                }

                if draft.audioURL != nil {
                    Section("Voice clip") {
                        Label("Audio attached", systemImage: "waveform")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle(editing == nil ? "New reminder" : "Edit reminder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { onClose(nil) }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { save() }
                        .bold()
                        .disabled(triggerType == .location && latitude == nil)
                }
            }
        }
    }

    private func save() {
        let cleanedText = draft.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let textForReminder = cleanedText.isEmpty ? "Reminder" : cleanedText
        let reminder: Reminder
        if let editing {
            // Preserve id + clientId so the row is UPDATED rather than duplicated.
            // Existing audio survives unless we're now adding a fresh recording on top.
            reminder = Reminder(
                id:           editing.id,
                clientId:     editing.clientId,
                text:         textForReminder,
                triggerAt:    triggerAt,
                completed:    false,
                completedAt:  nil,
                audioPath:    draft.audioURL?.path ?? editing.audioPath,
                recurrence:   recurrence,
                triggerType:  triggerType,
                latitude:     triggerType == .location ? latitude  : nil,
                longitude:    triggerType == .location ? longitude : nil,
                radiusMeters: triggerType == .location ? radius    : nil,
                placeLabel:   triggerType == .location ? placeLabel : nil,
                updatedAt:    Date(),
                dirty:        true,
                pendingDelete: false
            )
        } else {
            reminder = Reminder(
                text:         textForReminder,
                triggerAt:    triggerAt,
                audioPath:    draft.audioURL?.path,
                recurrence:   recurrence,
                triggerType:  triggerType,
                latitude:     triggerType == .location ? latitude  : nil,
                longitude:    triggerType == .location ? longitude : nil,
                radiusMeters: triggerType == .location ? radius    : nil,
                placeLabel:   triggerType == .location ? placeLabel : nil
            )
        }
        onClose(reminder)
    }

    private func useCurrentLocation() {
        Task {
            isLocating = true
            locationError = nil
            defer { isLocating = false }

            do {
                let location = try await locationManager.currentLocation()
                latitude  = location.coordinate.latitude
                longitude = location.coordinate.longitude
                placeLabel = await reverseGeocode(location)
            } catch {
                locationError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    private func reverseGeocode(_ location: CLLocation) async -> String? {
        let geocoder = CLGeocoder()
        do {
            let placemarks = try await geocoder.reverseGeocodeLocation(location)
            return placemarks.first?.name
                ?? placemarks.first?.thoroughfare
                ?? placemarks.first?.locality
                ?? "Pinned location"
        } catch {
            return "Pinned location"
        }
    }
}
