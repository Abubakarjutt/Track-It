import SwiftUI
import UIKit
import WorkoutLoggerCore
import WorkoutLoggerApp

/// Stock grouped form reached from the HUD's gear toolbar item: Units, Speech,
/// Exercises, Export, Data. Every control is a thin binding into `SettingsModel`.
///
/// The `Form` body is split into one `@ViewBuilder` property per section. SwiftUI
/// type-checks each small builder on its own; as a single expression the whole
/// form is more than the Swift 6 checker will resolve "in reasonable time".
struct SettingsView: View {
    let model: SettingsModel

    @Environment(\.scenePhase) private var scenePhase
    @State private var confirmingDelete = false
    @State private var choosingExportFormat = false
    @State private var shareURL: URL?

    var body: some View {
        Form {
            unitsSection
            speechSection
            exercisesSection
            exportSection
            healthSection
            privacySection
            deleteSection
        }
        .navigationTitle("Settings")
        .onAppear {
            model.recordSettingsOpened()
            model.refreshSpeechStatus()
            model.refreshHealthStatus()
            model.refreshHistory()
            model.refreshRecognitionReview()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                model.refreshSpeechStatus()
                model.refreshHealthStatus()
            }
        }
        .confirmationDialog(
            "Delete all workout data?", isPresented: $confirmingDelete, titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) { model.deleteAllWorkoutData() }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog(
            "Export format", isPresented: $choosingExportFormat, titleVisibility: .visible
        ) {
            Button("JSON — full backup") { presentExport(.json) }
            Button("CSV — spreadsheet") { presentExport(.csv) }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(isPresented: Binding(
            get: { shareURL != nil },
            set: { if !$0 { shareURL = nil } }
        )) {
            if let shareURL {
                ShareSheet(items: [shareURL])
            }
        }
    }

    @ViewBuilder private var unitsSection: some View {
        Section("Units") {
            Picker("Load unit", selection: Binding(
                get: { model.unit },
                set: { model.unit = $0 }
            )) {
                Text("Kilograms").tag(MassUnit.kilograms)
                Text("Pounds").tag(MassUnit.pounds)
            }
            .pickerStyle(.segmented)
        }
    }

    @ViewBuilder private var speechSection: some View {
        Section("Speech") {
            HStack {
                Text("Microphone access")
                Spacer()
                Text(statusText).foregroundStyle(.secondary)
            }
            if model.showsSpeechRecoveryRow {
                Button("Open iOS Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
            }
        }
    }

    @ViewBuilder private var exercisesSection: some View {
        Section("Exercises") {
            NavigationLink {
                ExerciseLibraryView(model: model)
            } label: {
                HStack {
                    Text("Exercise Library")
                    Spacer()
                    Text("\(model.exercises.count)").foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder private var exportSection: some View {
        Section {
            Button("Export Training History") { choosingExportFormat = true }
                .disabled(!model.canExportHistory)
        } footer: {
            Text(model.canExportHistory
                ? "Saves your full completed history as a file you can keep as a backup."
                : "Log and finish a workout first.")
        }
    }

    @ViewBuilder private var healthSection: some View {
        Section {
            HStack {
                Text("Write workouts to Apple Health")
                Spacer()
                Toggle("", isOn: Binding(
                    get: { model.healthSyncEnabled },
                    set: { enabled in Task { await model.setHealthSyncEnabled(enabled) } }
                ))
                .labelsHidden()
            }
            if model.showsHealthRecoveryRow {
                HStack {
                    Text(healthStatusText).foregroundStyle(.secondary)
                    Spacer()
                    Button("Open iOS Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                }
            }
        } header: {
            Text("Apple Health")
        } footer: {
            Text("Each finished workout is written once with a rough energy "
                + "estimate. trackit writes to Health and never reads from it.")
        }
    }

    @ViewBuilder private var privacySection: some View {
        Section {
            Toggle("Share anonymous analytics", isOn: Binding(
                get: { model.analyticsEnabled },
                set: { model.setAnalyticsEnabled($0) }
            ))
            Toggle("Help improve recognition", isOn: Binding(
                get: { model.recognitionReviewEnabled },
                set: { model.setRecognitionReviewEnabled($0) }
            ))
            if model.hasQueuedPhrases {
                NavigationLink {
                    RecognitionReviewView(model: model)
                } label: {
                    HStack {
                        Text("Review \(model.queuedPhraseCount) phrase\(model.queuedPhraseCount == 1 ? "" : "s")")
                        Spacer()
                        Text("tap to submit or discard").foregroundStyle(.secondary)
                    }
                }
            }
        } header: {
            Text("Privacy")
        } footer: {
            Text("Anonymous analytics send coarse usage only — never a "
                + "load, an exercise name, a transcript, or workout "
                + "content. A failed set can be queued for recognition "
                + "improvement; nothing is sent unless you submit it here.")
        }
    }

    @ViewBuilder private var deleteSection: some View {
        Section {
            Button("Delete All Workout Data", role: .destructive) {
                confirmingDelete = true
            }
            .disabled(!model.canDeleteAllWorkoutData)
        } footer: {
            Text(model.canDeleteAllWorkoutData
                ? "Deletes every logged workout. Your exercise library and preferences are kept."
                : "Finish your current workout first.")
        }
    }

    /// Write the export to a temp file named as the builder suggests, then hand
    /// that URL to the share sheet. A temp-write failure just leaves the sheet
    /// unopened — nothing in the app depends on the export succeeding.
    private func presentExport(_ format: ExportFormat) {
        let document = model.exportDocument(format: format)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(document.suggestedFilename)
        guard (try? document.data.write(to: url, options: .atomic)) != nil else { return }
        shareURL = url
    }

    private var statusText: String {
        switch model.speechStatus {
        case .granted: return "Granted"
        case .denied: return "Denied"
        case .notDetermined: return "Not determined"
        case .unavailable: return "Unavailable on this device"
        }
    }

    private var healthStatusText: String {
        switch model.healthSyncStatus {
        case .authorized: return "Granted"
        case .denied: return "Denied"
        case .notDetermined: return "Not determined"
        case .unavailable: return "Unavailable on this device"
        }
    }
}
