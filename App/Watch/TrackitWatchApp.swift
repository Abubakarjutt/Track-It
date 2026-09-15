import SwiftUI

/// The watch app has no functional UI (spec OPEN QUESTION 3 — "empty
/// shell") — it exists only because WidgetKit complications require a
/// companion watch app target to host the extension. It activates the
/// `WCSession` receiver so the complication's data stays current whenever
/// the watch app itself happens to launch, but the phone → complication
/// path does not depend on this app ever being opened.
@main
struct TrackitWatchApp: App {
    init() {
        WatchConnectivitySessionReceiver.shared.activate()
    }

    var body: some Scene {
        WindowGroup {
            VStack(spacing: 8) {
                Image(systemName: "figure.strengthtraining.traditional")
                    .font(.largeTitle)
                Text("Trackit")
                    .font(.headline)
            }
        }
    }
}
