import SwiftUI
import WorkoutLoggerCore
import WorkoutLoggerApp

/// The calm, high-contrast active-workout screen. A dumb renderer over
/// `HUDProjection` — no formatting or fallback logic lives here.
struct HUDView: View {
    let model: WorkoutSessionModel
    let historyUnavailable: Bool

    /// The two things that can cover the HUD. Tap-select is model-driven and
    /// wins if both are somehow up; the set list is a local swipe-up.
    private enum Sheet: Identifiable {
        case setList, tapSelect
        var id: Self { self }
    }

    @State private var showingSetList = false
    @State private var editingRow: EditRow?

    /// Identifiable wrapper so `.sheet(item:)` can carry the tapped row index.
    private struct EditRow: Identifiable { let id: Int }

    private var hud: HUDProjection { HUDProjection(from: model) }

    /// The active entry as a value (mirrors `HUDProjection.init(from:)`'s
    /// resolution), so the editor can be seeded with the real `LoggedSet`.
    private var activeEntry: Entry? {
        let entries = model.workout?.entries
        return model.activeExerciseName
            .flatMap { name in entries?.last { $0.exercise.name == name } }
            ?? entries?.last
    }

    private var activeSheet: Binding<Sheet?> {
        Binding(
            get: {
                if hud.tapSelectCandidates != nil { return .tapSelect }
                return showingSetList ? .setList : nil
            },
            set: { newValue in
                if newValue == nil {
                    showingSetList = false
                    model.dismissTapSelect() // no-op when there are no candidates
                }
            }
        )
    }

    var body: some View {
        VStack(spacing: 28) {
            if historyUnavailable {
                Text("History unavailable")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Text(hud.exerciseName)
                .font(.title2.weight(.semibold))
                .foregroundStyle(.white)

            Text(hud.lastSetLine ?? "—")
                .font(.system(size: 64, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .minimumScaleFactor(0.5)
                .lineLimit(1)

            restCard

            if let vs = hud.vsLastTimeLine {
                Text(vs)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            talkButton
        }
        .padding(32)
        .sheet(item: activeSheet) { sheet in
            switch sheet {
            case .setList:
                SetListSheet(
                    lines: hud.currentEntrySetLines,
                    onEdit: { index in editingRow = EditRow(id: index) },
                    onDelete: { index in model.removeActiveSet(index) }
                )
            case .tapSelect:
                TapSelectSheet(
                    candidates: hud.tapSelectCandidates ?? [],
                    onPick: { model.resolveTapSelect($0) }
                )
            }
        }
        .sheet(item: $editingRow) { row in
            if let set = activeEntry?.sets[safe: row.id] {
                NavigationStack {
                    SetEditView(
                        set: set,
                        exerciseNames: [],                 // no cross-exercise move mid-workout (out of scope)
                        unit: model.displayUnit,
                        onSave: { model.editActiveSet(row.id, to: $0.set) },
                        onDelete: { model.removeActiveSet(row.id) }
                    )
                }
            }
        }
        .gesture(
            DragGesture(minimumDistance: 20)
                .onEnded { value in if value.translation.height < -40 { showingSetList = true } }
        )
    }

    @ViewBuilder private var restCard: some View {
        if let restLine = hud.restLine {
            Text(restLine)
                .font(.system(size: 40, weight: .medium, design: .rounded))
                .foregroundStyle(hud.restTargetReached ? Color.green : Color.secondary)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(hud.restTargetReached ? Color.green : Color.secondary.opacity(0.4), lineWidth: 2)
                )
        }
    }

    private var talkButton: some View {
        Text(hud.isListening ? "Listening…" : "Hold to talk")
            .font(.title3.weight(.semibold))
            .foregroundStyle(.black)
            .frame(maxWidth: .infinity)
            .frame(height: 96)
            .background(
                RoundedRectangle(cornerRadius: 24)
                    .fill(hud.isListening ? Color.green : Color.white)
            )
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in if !model.isListening { model.pressed() } }
                    .onEnded { _ in Task { await model.released() } }
            )
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
