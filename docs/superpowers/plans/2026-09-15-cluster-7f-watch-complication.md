# Cluster 7f — Read-only Apple Watch Complication Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship a read-only Apple Watch complication showing "days since last
workout," fed by the phone over `WatchConnectivity`, with a hosting watch app
that is an empty shell.

**Architecture:** A new `TrackitWatch` (watchOS app, empty shell) and
`TrackitWatchWidgets` (watchOS widget extension) target pair, embedded in the
existing `Trackit` iOS app target. The phone computes the one fact
(`WorkoutHistoryModel.lastWorkoutEndedAt`, package-level, diffed inside the
existing `reload()` choke point) and pushes it opportunistically via
`WCSession.updateApplicationContext`. The watch app's `WCSessionDelegate`
receives it and writes it into an App-Group-shared `UserDefaults` suite; the
widget extension's `TimelineProvider` reads that suite and renders
`.accessoryCircular` + `.accessoryInline`. A `WatchSummary` wire struct
(Xcode-target-only, not in either Swift package, since it must compile for
watchOS which neither package targets) is the shared payload shape between
the phone app, the watch app, and the watch widget extension — the same
three-targets-share-one-file pattern already used for `WorkoutActivityAttributes`
(cluster 7c).

**Tech Stack:** Swift 6.0, watchOS 10.0 / iOS 17.0, `WatchConnectivity`,
`WidgetKit`, XcodeGen, `swift-testing`.

**Spec:** `docs/superpowers/specs/2026-09-11-cluster-7f-watch-complication.md`
(all 8 OPEN QUESTIONS resolved 2026-09-15 — the resolutions are this plan's
scope, most notably: primary fact = days since last workout; families =
circular + inline; empty-shell watch app; transport = `WatchConnectivity` now).

## Global Constraints

- Swift 6.0, Approachable Concurrency, `@MainActor` default (per repo-wide
  convention already in force).
- watchOS deployment target 10.0; iOS stays 17.0 (spec OPEN QUESTION 6).
- No `WorkoutLoggerCore` or `WorkoutLoggerApp` dependency on the watch side —
  the wire struct is primitives-only (spec point 3; also a hard platform
  constraint, since neither package targets watchOS).
- Package-level code must stay testable via `swift test` (Core) /
  `swift test --no-parallel` (App); App-target code (anything under `App/`)
  is verified only via `xcodegen generate && xcodebuild build` — no
  `swift test` coverage exists for `App/`, matching every prior cluster.
- Device verification (pairing a watch, adding the complication to a face,
  confirming refresh-budget behavior) is explicitly out of scope for this
  pass — tracked as this spec's last unticked Status box, same pattern as
  every prior cluster.
- Claude-Session trailer on every commit and the PR description (current
  session convention, overriding an earlier note to drop it — see memory).

---

### Task 1: `WorkoutHistoryModel.lastWorkoutEndedAt` + `WatchSummaryTransport` seam

**Files:**
- Create: `Packages/WorkoutLoggerApp/Sources/WorkoutLoggerApp/History/WatchSummaryTransport.swift`
- Create: `Packages/WorkoutLoggerApp/Sources/WorkoutLoggerApp/History/SpyWatchSummaryTransport.swift`
  (named `Fakes.swift` in the original draft — renamed: SwiftPM links object
  files by basename within a target, and `Session/Fakes.swift` already
  exists, so a second `Fakes.swift` anywhere else in this target fails the
  build with "multiple producers")
- Modify: `Packages/WorkoutLoggerApp/Sources/WorkoutLoggerApp/History/WorkoutHistoryModel.swift`
- Test: `Packages/WorkoutLoggerApp/Tests/WorkoutLoggerAppTests/WorkoutHistoryModelTests.swift`

**Interfaces:**
- Consumes: `WorkoutHistoryModel`'s existing `reload()` (the one choke point
  every mutation — `init`, `persist(_:_:)` used by `applyEdit`/`undo`/`redo`,
  `deleteWorkout`, `deleteAllWorkoutData` — already funnels through), and its
  existing `store: WorkoutHistoryStore` / `rows: [Workout]`.
- Produces: `public protocol WatchSummaryTransport: AnyObject { func send(lastWorkoutEndedAt: Date?) }`,
  `public final class NoOpWatchSummaryTransport: WatchSummaryTransport`,
  `public final class SpyWatchSummaryTransport: WatchSummaryTransport` (test
  fake, `sent: [Date?]`), and on `WorkoutHistoryModel`:
  `public private(set) var lastWorkoutEndedAt: Date?` and a new init param
  `watchTransport: WatchSummaryTransport = NoOpWatchSummaryTransport()`.
  Task 4's `SystemWatchSummaryTransport` (App-layer) conforms to this
  protocol; Task 5's `TimelineProvider` does not touch this protocol at all
  (it reads the App-Group cache Task 3/4 write, not this seam).

- [ ] **Step 1: Write the failing tests**

Add to `Packages/WorkoutLoggerApp/Tests/WorkoutLoggerAppTests/WorkoutHistoryModelTests.swift`
(reusing this file's existing `inMemoryStore()`, `working(_:_:)`,
`workout(started:ended:sets:)` helpers):

```swift
@Test("lastWorkoutEndedAt is the most recently completed workout's endedAt (cluster 7f)")
func lastWorkoutEndedAtTracksNewest() throws {
    let store = try inMemoryStore()
    store.save(workout(started: 1_000, ended: 1_500, sets: [working(100, 5)]))
    store.save(workout(started: 3_000, ended: 3_500, sets: [working(110, 5)]))
    // An open workout (no endedAt) must never win — it isn't in `rows`.
    store.save(workout(started: 5_000, ended: nil, sets: [working(120, 5)]))

    let model = WorkoutHistoryModel(store: store)

    #expect(model.lastWorkoutEndedAt == Date(timeIntervalSince1970: 3_500))
}

@Test("lastWorkoutEndedAt is nil with no completed workouts (cluster 7f)")
func lastWorkoutEndedAtNilWhenEmpty() throws {
    let store = try inMemoryStore()
    let model = WorkoutHistoryModel(store: store)
    #expect(model.lastWorkoutEndedAt == nil)
}

@Test("the watch transport fires at init and again only when the newest workout actually changes (cluster 7f)")
func watchTransportFiresOnRealChangesOnly() throws {
    let store = try inMemoryStore()
    store.save(workout(started: 1_000, ended: 1_500, sets: [working(100, 5)]))
    let transport = SpyWatchSummaryTransport()

    let model = WorkoutHistoryModel(store: store, watchTransport: transport)
    #expect(transport.sent == [Date(timeIntervalSince1970: 1_500)])

    // A reload with no underlying store change must not re-send.
    model.reload()
    #expect(transport.sent == [Date(timeIntervalSince1970: 1_500)])

    // A genuinely newer completed workout must re-send exactly once.
    store.save(workout(started: 3_000, ended: 3_500, sets: [working(110, 5)]))
    model.reload()
    #expect(transport.sent == [
        Date(timeIntervalSince1970: 1_500), Date(timeIntervalSince1970: 3_500),
    ])
}

@Test("deleting the newest workout re-sends the new-newest (or nil) value (cluster 7f)")
func watchTransportFiresOnDelete() throws {
    let store = try inMemoryStore()
    store.save(workout(started: 1_000, ended: 1_500, sets: [working(100, 5)]))
    let newest = workout(started: 3_000, ended: 3_500, sets: [working(110, 5)])
    store.save(newest)
    let transport = SpyWatchSummaryTransport()
    let model = WorkoutHistoryModel(store: store, watchTransport: transport)
    #expect(transport.sent == [Date(timeIntervalSince1970: 3_500)])

    model.deleteWorkout(newest)

    #expect(transport.sent == [
        Date(timeIntervalSince1970: 3_500), Date(timeIntervalSince1970: 1_500),
    ])
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd Packages/WorkoutLoggerApp && swift test --no-parallel --filter WorkoutHistoryModelTests`
Expected: FAIL — `value of type 'WorkoutHistoryModel' has no member 'lastWorkoutEndedAt'` /
`cannot find type 'SpyWatchSummaryTransport' in scope` / extra `watchTransport:` argument error.

- [ ] **Step 3: Implement**

`Packages/WorkoutLoggerApp/Sources/WorkoutLoggerApp/History/WatchSummaryTransport.swift`:

```swift
import Foundation

/// Sends the watch's one glanceable fact — the most recently completed
/// workout's `endedAt`, or `nil` — to a paired Apple Watch (cluster 7f,
/// spec OPEN QUESTION 1/4). Primitive-typed so this package needn't depend
/// on any watch-only wire type: `SystemWatchSummaryTransport` (App-layer,
/// Task 4) builds the real `WatchConnectivity` payload — a `WatchSummary`
/// struct that lives in `App/Watch/Shared` because it must compile for
/// watchOS, which this package does not target — from the `Date?` this
/// hands it.
@MainActor
public protocol WatchSummaryTransport: AnyObject {
    func send(lastWorkoutEndedAt: Date?)
}

/// Default when no paired watch matters (every existing call site, tests
/// unrelated to this seam).
public final class NoOpWatchSummaryTransport: WatchSummaryTransport {
    public init() {}
    public func send(lastWorkoutEndedAt: Date?) {}
}
```

`Packages/WorkoutLoggerApp/Sources/WorkoutLoggerApp/History/Fakes.swift`:

```swift
import Foundation

/// Records every `send` call for the watch-transport tests (cluster 7f).
public final class SpyWatchSummaryTransport: WatchSummaryTransport {
    public private(set) var sent: [Date?] = []
    public init() {}
    public func send(lastWorkoutEndedAt: Date?) { sent.append(lastWorkoutEndedAt) }
}
```

In `WorkoutHistoryModel.swift`, add the stored property and transport
dependency next to the existing ones, extend `init`, and diff inside
`reload()`:

```swift
    /// The most recently completed workout's `endedAt`, or `nil` — the one
    /// fact cluster 7f's watch complication shows. Kept in lockstep with
    /// `rows` inside `reload()`, which already runs after every mutation.
    public private(set) var lastWorkoutEndedAt: Date?

    @ObservationIgnored private let watchTransport: WatchSummaryTransport
```

```swift
    public init(
        store: WorkoutHistoryStore, historyUnavailable: Bool = false,
        watchTransport: WatchSummaryTransport = NoOpWatchSummaryTransport()
    ) {
        self.store = store
        self.isUnavailable = historyUnavailable
        self.watchTransport = watchTransport
        reload()
    }

    public func reload() {
        let previousLastWorkoutEndedAt = lastWorkoutEndedAt
        rows = isUnavailable ? [] : Array(store.history().filter(\.isEnded).reversed())
        lastWorkoutEndedAt = rows.first?.endedAt
        if lastWorkoutEndedAt != previousLastWorkoutEndedAt {
            watchTransport.send(lastWorkoutEndedAt: lastWorkoutEndedAt)
        }
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd Packages/WorkoutLoggerApp && swift test --no-parallel --filter WorkoutHistoryModelTests`
Expected: PASS, all 4 new tests plus every existing test in the file.

Then run the full App suite to confirm nothing else broke:
Run: `cd Packages/WorkoutLoggerApp && swift test --no-parallel`
Expected: PASS, 277 → 281.

- [ ] **Step 5: Commit**

```bash
git add Packages/WorkoutLoggerApp/Sources/WorkoutLoggerApp/History/WatchSummaryTransport.swift \
        Packages/WorkoutLoggerApp/Sources/WorkoutLoggerApp/History/Fakes.swift \
        Packages/WorkoutLoggerApp/Sources/WorkoutLoggerApp/History/WorkoutHistoryModel.swift \
        Packages/WorkoutLoggerApp/Tests/WorkoutLoggerAppTests/WorkoutHistoryModelTests.swift
git commit -m "feat(7f): WorkoutHistoryModel.lastWorkoutEndedAt + WatchSummaryTransport seam

Claude-Session: https://claude.ai/code/session_01NPXLzSUXbBwoLLFVo2hg6z"
```

---

### Task 2: watchOS app + widget-extension targets in `project.yml`

**Files:**
- Modify: `project.yml`
- Create: `App/Watch/Info.plist`
- Create: `App/Watch/TrackitWatch.entitlements`
- Create: `App/WatchWidgets/Info.plist`
- Create: `App/WatchWidgets/TrackitWatchWidgets.entitlements`

**Interfaces:**
- Consumes: nothing from Task 1.
- Produces: the `TrackitWatch` (watchOS app) and `TrackitWatchWidgets`
  (watchOS widget extension) targets that Tasks 3–5's source files compile
  into. Both share app group `group.com.abubakarsahi.trackit.watch`.

This task adds empty-shell scaffolding only — no Swift source yet beyond
what XcodeGen needs to resolve the targets, so it is verified by
`xcodegen generate` succeeding, not by a successful `xcodebuild` (Task 3
provides the first real source files each target needs to compile).

- [ ] **Step 1: Add the watchOS deployment target and re-shape `Trackit`'s sources**

In `project.yml`, add `watchOS: "10.0"` to `options.deploymentTarget`, and
extend `Trackit`'s exclude list + add the new `App/Watch/Shared` source path
and the `TrackitWatch` embed dependency:

```yaml
options:
  bundleIdPrefix: com.abubakarsahi
  deploymentTarget:
    iOS: "17.0"
    watchOS: "10.0"
  createIntermediateGroups: true
```

```yaml
  Trackit:
    type: application
    platform: iOS
    sources:
      # Widgets/** and Watch/**/WatchWidgets/** are excluded here and picked
      # up by TrackitWidgets/TrackitWatch/TrackitWatchWidgets below instead
      # — their Swift files (a second @main, watch-only WidgetKit code) must
      # not also compile into the iOS app target. The two Shared dirs are
      # the one part multiple targets need, so each is re-added explicitly.
      - path: App
        excludes:
          - "Tests/**"
          - "Widgets/**"
          - "Watch/**"
          - "WatchWidgets/**"
      - path: App/Widgets/Shared
      - path: App/Watch/Shared
    settings:
      base:
        TARGETED_DEVICE_FAMILY: "1"
        SWIFT_VERSION: "6.0"
        INFOPLIST_FILE: App/Info.plist
        CODE_SIGN_ENTITLEMENTS: App/Trackit.entitlements
        PRODUCT_BUNDLE_IDENTIFIER: com.abubakarsahi.trackit
    dependencies:
      - package: WorkoutLoggerCore
        product: WorkoutLoggerCore
      - package: WorkoutLoggerApp
        product: WorkoutLoggerApp
      - target: TrackitWidgets
        embed: true
      - target: TrackitWatch
        embed: true
```

- [ ] **Step 2: Add the two new targets**

Append after `TrackitWidgets`:

```yaml
  TrackitWatch:
    type: application
    platform: watchOS
    sources:
      - path: App/Watch
    settings:
      base:
        TARGETED_DEVICE_FAMILY: "4"
        SWIFT_VERSION: "6.0"
        INFOPLIST_FILE: App/Watch/Info.plist
        CODE_SIGN_ENTITLEMENTS: App/Watch/TrackitWatch.entitlements
        PRODUCT_BUNDLE_IDENTIFIER: com.abubakarsahi.trackit.watch
        SKIP_INSTALL: "NO"
    dependencies:
      - target: TrackitWatchWidgets
        embed: true
  TrackitWatchWidgets:
    type: app-extension
    platform: watchOS
    sources:
      - path: App/WatchWidgets
      - path: App/Watch/Shared
    settings:
      base:
        TARGETED_DEVICE_FAMILY: "4"
        SWIFT_VERSION: "6.0"
        INFOPLIST_FILE: App/WatchWidgets/Info.plist
        CODE_SIGN_ENTITLEMENTS: App/WatchWidgets/TrackitWatchWidgets.entitlements
        PRODUCT_BUNDLE_IDENTIFIER: com.abubakarsahi.trackit.watch.widgets
        SKIP_INSTALL: "NO"
```

- [ ] **Step 3: Write the four new plist/entitlements files**

`App/Watch/Info.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDisplayName</key>
    <string>Trackit</string>
    <key>CFBundleIdentifier</key>
    <string>$(PRODUCT_BUNDLE_IDENTIFIER)</string>
    <key>CFBundleExecutable</key>
    <string>$(EXECUTABLE_NAME)</string>
    <key>CFBundlePackageType</key>
    <string>$(PRODUCT_BUNDLE_PACKAGE_TYPE)</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>WKApplication</key>
    <true/>
    <key>WKCompanionAppBundleIdentifier</key>
    <string>com.abubakarsahi.trackit</string>
</dict>
</plist>
```

`App/Watch/TrackitWatch.entitlements`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.application-groups</key>
    <array>
        <string>group.com.abubakarsahi.trackit.watch</string>
    </array>
</dict>
</plist>
```

`App/WatchWidgets/Info.plist` (mirrors `App/Widgets/Info.plist`):

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDisplayName</key>
    <string>TrackitWatchWidgets</string>
    <key>CFBundleIdentifier</key>
    <string>$(PRODUCT_BUNDLE_IDENTIFIER)</string>
    <key>CFBundleExecutable</key>
    <string>$(EXECUTABLE_NAME)</string>
    <key>CFBundlePackageType</key>
    <string>$(PRODUCT_BUNDLE_PACKAGE_TYPE)</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>NSExtension</key>
    <dict>
        <key>NSExtensionPointIdentifier</key>
        <string>com.apple.widgetkit-extension</string>
    </dict>
</dict>
</plist>
```

`App/WatchWidgets/TrackitWatchWidgets.entitlements` — identical content to
`App/Watch/TrackitWatch.entitlements` above (same app group, both watch-side
targets).

- [ ] **Step 4: Verify**

Run: `xcodegen generate`
Expected: succeeds and reports both new targets created. `xcodebuild` is not
expected to succeed yet — `App/Watch` and `App/WatchWidgets` have no Swift
source files until Task 3, so XcodeGen may warn about empty source paths;
that warning is expected and resolves once Task 3 lands.

- [ ] **Step 5: Commit**

```bash
git add project.yml App/Watch/Info.plist App/Watch/TrackitWatch.entitlements \
        App/WatchWidgets/Info.plist App/WatchWidgets/TrackitWatchWidgets.entitlements
git commit -m "feat(7f): watchOS app + widget-extension target scaffolding

Claude-Session: https://claude.ai/code/session_01NPXLzSUXbBwoLLFVo2hg6z"
```

---

### Task 3: Shared `WatchSummary` wire struct + watch-side WCSession receiver + empty-shell watch app

**Files:**
- Create: `App/Watch/Shared/WatchSummary.swift`
- Create: `App/Watch/System/WatchConnectivitySessionReceiver.swift`
- Create: `App/Watch/TrackitWatchApp.swift`

**Interfaces:**
- Consumes: nothing from Task 1 (deliberately — this file must not import
  either Swift package; see Global Constraints).
- Produces: `WatchSummary` (used by Task 4's phone-side transport to encode,
  and by Task 5's `TimelineProvider` to decode), and the App-Group
  `UserDefaults` key (`"watchSummary"`, suite
  `group.com.abubakarsahi.trackit.watch`) Task 5 reads from.

- [ ] **Step 1: The shared wire struct**

`App/Watch/Shared/WatchSummary.swift`:

```swift
import Foundation

/// The one glanceable fact cluster 7f's watch complication shows, encoded
/// over `WatchConnectivity` and cached in an App-Group `UserDefaults` suite
/// on the watch side. Deliberately primitives-only with no
/// `WorkoutLoggerCore`/`WorkoutLoggerApp` dependency: this file compiles
/// into the iOS `Trackit` target, the watchOS `TrackitWatch` app, and the
/// watchOS `TrackitWatchWidgets` extension (see `project.yml`), and neither
/// Swift package targets watchOS.
public struct WatchSummary: Codable, Equatable, Sendable {
    /// The most recently completed workout's `endedAt`, or `nil` with no
    /// completed workouts yet.
    public let lastWorkoutEndedAt: Date?

    public init(lastWorkoutEndedAt: Date?) {
        self.lastWorkoutEndedAt = lastWorkoutEndedAt
    }
}

/// Where the watch-side `WatchConnectivity` receiver (below) writes the
/// latest summary, and where the widget extension's `TimelineProvider`
/// (Task 5) reads it from — the two watch-side processes don't share
/// memory, only this App Group suite.
public enum WatchSummaryStorage {
    public static let appGroupSuiteName = "group.com.abubakarsahi.trackit.watch"
    public static let userDefaultsKey = "watchSummary"

    public static func read() -> WatchSummary? {
        guard let data = UserDefaults(suiteName: appGroupSuiteName)?.data(forKey: userDefaultsKey)
        else { return nil }
        return try? JSONDecoder().decode(WatchSummary.self, from: data)
    }

    public static func write(_ summary: WatchSummary) {
        guard let data = try? JSONEncoder().encode(summary) else { return }
        UserDefaults(suiteName: appGroupSuiteName)?.set(data, forKey: userDefaultsKey)
    }
}
```

- [ ] **Step 2: The watch-side `WCSessionDelegate`**

`App/Watch/System/WatchConnectivitySessionReceiver.swift`:

```swift
import Foundation
import WatchConnectivity
import WidgetKit

/// Activates `WCSession` on the watch and, whenever the phone pushes a
/// fresh `WatchSummary` via `updateApplicationContext`, writes it into the
/// shared App Group suite and asks WidgetKit to reload the complication.
/// `NSObject` conformance is required by `WCSessionDelegate`. A singleton
/// (`shared`) retained for the watch app's lifetime by `TrackitWatchApp`
/// below — mirrors the phone-side `System*` adapters' retained-singleton
/// pattern (cluster 7b/7c).
final class WatchConnectivitySessionReceiver: NSObject, WCSessionDelegate {
    static let shared = WatchConnectivitySessionReceiver()

    private override init() {}

    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {}

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        guard let data = applicationContext["summary"] as? Data,
              let summary = try? JSONDecoder().decode(WatchSummary.self, from: data)
        else { return }
        WatchSummaryStorage.write(summary)
        WidgetCenter.shared.reloadAllTimelines()
    }
}
```

- [ ] **Step 3: The empty-shell watch app**

`App/Watch/TrackitWatchApp.swift`:

```swift
import SwiftUI

/// The watch app has no functional UI (spec OPEN QUESTION 3 — "empty
/// shell") — it exists only because WidgetKit complications require a
/// companion watch app target to host the extension. It activates the
/// `WCSession` receiver so the complication's data stays current whenever
/// the watch app itself happens to launch, but the phone → complication
/// path (Tasks 4–5) does not depend on this app ever being opened.
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
```

- [ ] **Step 4: Verify**

Run: `xcodegen generate && xcodebuild -project Trackit.xcodeproj -scheme TrackitWatch -destination 'generic/platform=watchOS Simulator' build`
Expected: `** BUILD SUCCEEDED **` for the `TrackitWatch` scheme (the widget
extension target still has no source yet — Task 5 — so building the whole
`Trackit` scheme is deferred to Task 5's verification step).

- [ ] **Step 5: Commit**

```bash
git add App/Watch/Shared/WatchSummary.swift \
        App/Watch/System/WatchConnectivitySessionReceiver.swift \
        App/Watch/TrackitWatchApp.swift
git commit -m "feat(7f): WatchSummary wire struct + watch-side WCSession receiver + empty-shell watch app

Claude-Session: https://claude.ai/code/session_01NPXLzSUXbBwoLLFVo2hg6z"
```

---

### Task 4: Phone-side `SystemWatchSummaryTransport` + `TrackitApp` wiring

**Files:**
- Create: `App/System/SystemWatchSummaryTransport.swift`
- Modify: `App/TrackitApp.swift`

**Interfaces:**
- Consumes: `WatchSummaryTransport` (Task 1, package). Also constructs and
  encodes `WatchSummary` (Task 3, `App/Watch/Shared`, already compiled into
  the `Trackit` target per Task 2's source re-inclusion) — the phone doesn't
  share the watch's App Group, only the `"summary"` dictionary key used for
  `updateApplicationContext`, matching what Task 3's receiver reads.
- Produces: `SystemWatchSummaryTransport`, passed as `WorkoutHistoryModel`'s
  `watchTransport:` argument in `TrackitApp.init()`.

- [ ] **Step 1: The phone-side transport**

`App/System/SystemWatchSummaryTransport.swift`:

```swift
import Foundation
import WatchConnectivity
import WorkoutLoggerApp

/// Real `WatchConnectivity`-backed `WatchSummaryTransport` (cluster 7f).
/// `updateApplicationContext` is "latest value wins, delivered
/// opportunistically" — exactly the read-only, eventually-consistent
/// promise spec OPEN QUESTION 5 confirms. `NSObject` conformance is
/// required by `WCSessionDelegate`; the delegate methods below are
/// required by the protocol on this platform even though this type sends
/// and never receives.
final class SystemWatchSummaryTransport: NSObject, WatchSummaryTransport, WCSessionDelegate {
    override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func send(lastWorkoutEndedAt: Date?) {
        guard WCSession.isSupported(), WCSession.default.activationState == .activated else { return }
        let summary = WatchSummary(lastWorkoutEndedAt: lastWorkoutEndedAt)
        guard let data = try? JSONEncoder().encode(summary) else { return }
        try? WCSession.default.updateApplicationContext(["summary": data])
    }

    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {}

    func sessionDidBecomeInactive(_ session: WCSession) {}

    func sessionDidDeactivate(_ session: WCSession) {
        // A new watch may be paired next — re-activate for it (Apple's
        // documented pattern for this callback).
        WCSession.default.activate()
    }
}
```

- [ ] **Step 2: Wire it into `TrackitApp.init()`**

In `App/TrackitApp.swift`, construct the transport before `historyModel` and
pass it through:

```swift
        let watchSummaryTransport = SystemWatchSummaryTransport()
        self.historyModel = WorkoutHistoryModel(
            store: store, historyUnavailable: availability.isDegraded,
            watchTransport: watchSummaryTransport
        )
```

(replacing the existing two-argument `WorkoutHistoryModel(store:historyUnavailable:)`
call at the same spot). No stored property needed for the transport itself —
unlike `remotePushToTalk`/`liveActivity`/`restNotifications`, nothing needs
to keep it alive beyond `historyModel`'s own retention of it as
`watchTransport`, since `WorkoutHistoryModel` holds the only reference this
app needs.

- [ ] **Step 3: Verify**

Run: `xcodegen generate && xcodebuild -project Trackit.xcodeproj -scheme Trackit -destination 'generic/platform=iOS Simulator' build`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Commit**

```bash
git add App/System/SystemWatchSummaryTransport.swift App/TrackitApp.swift
git commit -m "feat(7f): phone-side SystemWatchSummaryTransport, wired into TrackitApp

Claude-Session: https://claude.ai/code/session_01NPXLzSUXbBwoLLFVo2hg6z"
```

---

### Task 5: Watch widget extension — `TimelineProvider` + complication views

**Files:**
- Create: `App/WatchWidgets/TrackitWatchWidgetsBundle.swift`
- Create: `App/WatchWidgets/DaysSinceLastWorkoutComplication.swift`

**Interfaces:**
- Consumes: `WatchSummary` / `WatchSummaryStorage.read()` (Task 3,
  `App/Watch/Shared`, already compiled into this target per Task 2's
  `TrackitWatchWidgets` source list).
- Produces: the `DaysSinceLastWorkoutComplication` widget, families
  `.accessoryCircular` + `.accessoryInline` (spec OPEN QUESTION 2).

- [ ] **Step 1: The widget bundle**

`App/WatchWidgets/TrackitWatchWidgetsBundle.swift`:

```swift
import WidgetKit
import SwiftUI

@main
struct TrackitWatchWidgetsBundle: WidgetBundle {
    var body: some Widget {
        DaysSinceLastWorkoutComplication()
    }
}
```

- [ ] **Step 2: The complication**

`App/WatchWidgets/DaysSinceLastWorkoutComplication.swift`:

```swift
import WidgetKit
import SwiftUI

/// Days since the last completed workout, read from the App Group cache
/// `WatchConnectivitySessionReceiver` (the watch app, Task 3) writes.
/// Refreshes on a WidgetKit-triggered reload (a fresh phone push while the
/// watch app is reachable) and, independently, at each local midnight so
/// the count advances even with no new push in between — spec OPEN
/// QUESTION 5's "eventually consistent, not real-time" promise.
struct DaysSinceLastWorkoutEntry: TimelineEntry {
    let date: Date
    let lastWorkoutEndedAt: Date?

    var daysSinceLastWorkout: Int? {
        guard let lastWorkoutEndedAt else { return nil }
        return Calendar.current.dateComponents([.day], from: lastWorkoutEndedAt, to: date).day
    }
}

struct DaysSinceLastWorkoutProvider: TimelineProvider {
    func placeholder(in context: Context) -> DaysSinceLastWorkoutEntry {
        DaysSinceLastWorkoutEntry(date: Date(), lastWorkoutEndedAt: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (DaysSinceLastWorkoutEntry) -> Void) {
        completion(currentEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<DaysSinceLastWorkoutEntry>) -> Void) {
        let entry = currentEntry()
        let nextMidnight = Calendar.current.nextDate(
            after: Date(), matching: DateComponents(hour: 0, minute: 0, second: 0),
            matchingPolicy: .nextTime
        ) ?? Date().addingTimeInterval(3_600)
        completion(Timeline(entries: [entry], policy: .after(nextMidnight)))
    }

    private func currentEntry() -> DaysSinceLastWorkoutEntry {
        DaysSinceLastWorkoutEntry(date: Date(), lastWorkoutEndedAt: WatchSummaryStorage.read()?.lastWorkoutEndedAt)
    }
}

struct DaysSinceLastWorkoutComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "DaysSinceLastWorkout", provider: DaysSinceLastWorkoutProvider()) { entry in
            DaysSinceLastWorkoutView(entry: entry)
        }
        .configurationDisplayName("Days Since Workout")
        .description("Days since your last logged workout.")
        .supportedFamilies([.accessoryCircular, .accessoryInline])
    }
}

private struct DaysSinceLastWorkoutView: View {
    let entry: DaysSinceLastWorkoutEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .accessoryInline:
            Text(inlineText)
        default:
            VStack(spacing: 0) {
                Text(valueText)
                    .font(.title3.monospacedDigit())
                Text("days")
                    .font(.caption2)
            }
        }
    }

    private var valueText: String {
        guard let days = entry.daysSinceLastWorkout else { return "–" }
        return "\(days)"
    }

    private var inlineText: String {
        guard let days = entry.daysSinceLastWorkout else { return "No workouts yet" }
        return days == 0 ? "Workout today" : "\(days)d since workout"
    }
}
```

- [ ] **Step 3: Verify — full build, both platforms**

Run:
```bash
xcodegen generate
xcodebuild -project Trackit.xcodeproj -scheme Trackit -destination 'generic/platform=iOS Simulator' build
xcodebuild -project Trackit.xcodeproj -scheme TrackitWatch -destination 'generic/platform=watchOS Simulator' build
```
Expected: `** BUILD SUCCEEDED **` for both (the `Trackit` scheme build
exercises `TrackitWidgets` + the now-embedded `TrackitWatch` app +
`TrackitWatchWidgets` extension transitively; the `TrackitWatch` scheme
build is the direct check that the watch app + its widget extension compile
and link standalone).

- [ ] **Step 4: Commit**

```bash
git add App/WatchWidgets/TrackitWatchWidgetsBundle.swift \
        App/WatchWidgets/DaysSinceLastWorkoutComplication.swift
git commit -m "feat(7f): DaysSinceLastWorkout complication — TimelineProvider + circular/inline views

Claude-Session: https://claude.ai/code/session_01NPXLzSUXbBwoLLFVo2hg6z"
```

---

### Task 6: Verification, two-axis review, PR, merge, memory updates

**Files:** none new — this task runs the existing `finishing-a-development-branch`
rhythm used for every prior cluster.

- [ ] **Step 1: Full test + build pass**

```bash
cd Packages/WorkoutLoggerCore && swift test
cd Packages/WorkoutLoggerApp && swift test --no-parallel
cd /Users/Apple/projects/trackit
xcodegen generate
xcodebuild -project Trackit.xcodeproj -scheme Trackit -destination 'generic/platform=iOS Simulator' build
xcodebuild -project Trackit.xcodeproj -scheme TrackitWatch -destination 'generic/platform=watchOS Simulator' build
```
Expected: Core 169/169 unchanged; App 277 → 281 green; both `xcodebuild`
invocations `** BUILD SUCCEEDED **`.

- [ ] **Step 2: Two-axis code review**

Use `mattpocock-skills:code-review`. Fixed point: the commit this branch
forked from (`git merge-base main HEAD`, or the last `main` commit before
this branch's first commit — record it explicitly when dispatching). Spec:
`docs/superpowers/specs/2026-09-11-cluster-7f-watch-complication.md`
(resolved OPEN QUESTIONS + Status section are authoritative). Fold any
findings, re-run Step 1's full verification after folding.

- [ ] **Step 3: Tick the spec's Status checklist**

In `docs/superpowers/specs/2026-09-11-cluster-7f-watch-complication.md`,
tick every box except "paired-watch device verification" (explicitly
device-only, deferred like every prior cluster).

- [ ] **Step 4: PR + merge**

```bash
git push -u origin v1.1-cluster-7f-watch-complication
gh pr create --base main --head v1.1-cluster-7f-watch-complication \
  --title "Cluster 7f: read-only Apple Watch complication" \
  --body "…summary + Claude-Session trailer…"
gh pr merge <N> --rebase --delete-branch
git fetch origin --prune
```
Expected: `origin/main` == local `main` after merge; remote feature branch
deleted; no local branch left over (matches the `gh pr merge` fast-forward
behavior observed on this machine in cluster 7c).

- [ ] **Step 5: Update roadmap + memory**

Update `docs/superpowers/specs/2026-09-11-v1.1-remaining-INDEX.md` (mark 7f
merged, in both its status table and its recommended-order table), and
append an entry to the persistent memory files (`phase-progress.md`,
`MEMORY.md`) following the exact style used for every prior cluster's
completion entry.

## Self-Review Notes

- **Spec coverage:** all 5 numbered work items (new targets, transport,
  `WatchSummary`, phone publisher, watch timeline provider) map to Tasks
  1–5. All 3 package-level acceptance tests are covered by Task 1's 4 tests
  (test 1's Codable round-trip is not separately unit-tested — see below).
  Device-only acceptance tests 4–7 are out of scope per the spec's own
  Status box and every prior cluster's precedent.
- **Placeholder scan:** none found — every step has complete code, not a
  description of code.
- **Type consistency:** `WatchSummaryTransport.send(lastWorkoutEndedAt:)`,
  `WatchSummary.lastWorkoutEndedAt`, `WatchSummaryStorage.read()/.write(_:)`,
  and `DaysSinceLastWorkoutEntry.lastWorkoutEndedAt` all agree on the same
  `Date?` shape end to end, phone to watch.
- **A deliberate deviation from the spec's own suggestion, recorded here
  rather than silently changed:** the spec's point 3 floats "a small
  `WorkoutLoggerApp` addition: a single `watchSummary` computed property
  that bundles the 1–3 facts" as a package-level `WatchSummary`-shaped
  type. This plan does NOT define `WatchSummary` in the package — only a
  plain `Date?` (`WorkoutHistoryModel.lastWorkoutEndedAt`). Reason: the
  package targets iOS/macOS only, never watchOS, so a package-level
  `WatchSummary` could never be the same type the watch decodes — Swift
  Packages cannot be imported by the Xcode-target files that must reach
  watchOS, and the reverse (the package importing an App-target file) is
  not a valid dependency direction either. With exactly one fact in scope
  (spec OPEN QUESTION 1's resolution), a bundling struct at the package
  level would carry one field and buy nothing a computed `Date?` doesn't
  already give, so this plan keeps the package-level API to that one
  property and puts the actual wire struct only where it must live —
  `App/Watch/Shared`, shared by all three App-target consumers. If a future
  cluster adds a second or third fact to the complication, revisit whether
  a package-level bundling type earns its keep then.
- **Acceptance test 1 ("`WatchSummary` round-trips through Codable") is not
  separately unit-tested.** `WatchSummary` lives in `App/Watch/Shared`, an
  Xcode-target file tree with no `swift test`-invokable target — the same
  structural gap `WorkoutActivityAttributes.ContentState` (cluster 7c) had,
  and that cluster's plan made the same call: `Codable` synthesis over one
  primitive field is low enough risk, and high enough cost to test outside
  a package (a throwaway XCTest target, or hand-verification via the
  debugger), that it's accepted as covered by the `xcodebuild` build check
  plus Task 1's tests (which exercise the exact same shape one layer down,
  as a plain `Date?`) rather than given its own test target.
