import SwiftUI
import UIKit
import WorkoutLoggerCore
import WorkoutLoggerApp

/// Stock grouped form reached from the HUD's gear toolbar item: Units, Speech,
/// Exercises, Export, Data. Every control is a thin binding into `SettingsModel`.
struct SettingsView: View {
    let model: SettingsModel

    @Environment(\.scenePhase) private var scenePhase
    @State private var confirmingDelete = false
    @State private var choosingExportFormat = false
    @State private var shareURL: URL?

    var body: some View {
        Form {
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

            Section {
                Button("Export Training History") { choosingExportFormat = true }
                    .disabled(!model.canExportHistory)
            } footer: {
                Text(model.canExportHistory
                     ? "Saves your full completed history as a file you can keep as a backup."
                     : "Log and finish a workout first.")
            }

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
        .navigationTitle("Settings")
        .onAppear {
            model.refreshSpeechStatus()
            model.refreshHistory()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { model.refreshSpeechStatus() }
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
}
