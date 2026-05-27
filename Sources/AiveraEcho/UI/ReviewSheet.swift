import CoreLocation
import SwiftUI

struct ReviewDraft: Identifiable {
    let id = UUID()
    var text: String
    var audioURL: URL?
}

struct ReviewSheet: View {
    @State var draft: ReviewDraft
    let onClose: (Reminder?) -> Void

    @EnvironmentObject private var locationManager: LocationManager

    // Time trigger
    @State private var triggerAt: Date = Date().addingTimeInterval(60 * 60)
    @State private var recurrence: Recurrence = .none

    // Trigger type picker
    @State private var triggerType: TriggerType = .time

    // Place trigger
    @State private var latitude: Double?
    @State private var longitude: Double?
    @State private var placeLabel: String?
    @State private var radius: Double = 200
    @State private var isLocating = false
    @State private var locationError: String?

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
            .navigationTitle("New reminder")
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
        let reminder = Reminder(
            text:         draft.text.trimmingCharacters(in: .whitespacesAndNewlines),
            triggerAt:    triggerAt,
            audioPath:    draft.audioURL?.path,
            recurrence:   recurrence,
            triggerType:  triggerType,
            latitude:     triggerType == .location ? latitude  : nil,
            longitude:    triggerType == .location ? longitude : nil,
            radiusMeters: triggerType == .location ? radius    : nil,
            placeLabel:   triggerType == .location ? placeLabel : nil
        )
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
