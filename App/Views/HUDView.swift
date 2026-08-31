import SwiftUI
import WorkoutLoggerCore
import WorkoutLoggerApp

/// The calm, high-contrast active-workout screen. A dumb renderer over
/// `HUDProjection` — no formatting or fallback logic lives here.
struct HUDView: View {
    let model: WorkoutSessionModel
    let historyUnavailable: Bool

    @State private var showingSetList = false

    private var hud: HUDProjection { HUDProjection(from: model) }

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

            Spacer()

            talkButton
        }
        .padding(32)
        .sheet(isPresented: $showingSetList) {
            SetListSheet(lines: hud.currentEntrySetLines)
        }
        .sheet(isPresented: Binding(
            get: { hud.tapSelectCandidates != nil },
            set: { if !$0 { /* dismissed without choosing — no-op */ } }
        )) {
            TapSelectSheet(
                candidates: hud.tapSelectCandidates ?? [],
                onPick: { model.resolveTapSelect($0) }
            )
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
