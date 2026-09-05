import SwiftUI
import UIKit
import WorkoutLoggerCore
import WorkoutLoggerApp

/// Stock grouped form reached from the HUD's gear toolbar item: Units, Speech,
/// Exercises, Data. Every control is a thin binding into `SettingsModel`.
struct SettingsView: View {
    let model: SettingsModel

    @Environment(\.scenePhase) private var scenePhase
    @State private var confirmingDelete = false

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
        .onAppear { model.refreshSpeechStatus() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { model.refreshSpeechStatus() }
        }
        .confirmationDialog(
            "Delete all workout data?", isPresented: $confirmingDelete, titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) { model.deleteAllWorkoutData() }
            Button("Cancel", role: .cancel) {}
        }
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
