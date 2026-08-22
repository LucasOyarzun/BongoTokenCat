import AppKit
import Observation

/// Drives the paw animation.
///
/// `TimelineView(.animation)` is the obvious tool and it does not work here: it
/// rides the display link, which macOS does not run reliably for a background
/// accessory app's floating panel — the cats render correctly and then never move.
/// An explicit timer publishing a clock value is boring and it actually ticks.
///
/// It runs only while something is drumming. An idle fleet costs nothing, which is
/// the whole point of an app that sits on screen all day.
@MainActor
@Observable
final class DrumClock {
    private(set) var now = Date()

    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var activity: NSObjectProtocol?

    /// Fast enough for a 12 Hz strike to look like a strike rather than a stutter.
    private static let tickInterval: TimeInterval = 1.0 / 24.0

    var isRunning: Bool { timer != nil }

    func start() {
        guard timer == nil else { return }
        // App Nap throttles background timers to about once a second, which would
        // turn the drumming into a twitch. This tells the system the animation is
        // deliberate, while still allowing the display to sleep.
        activity = ProcessInfo.processInfo.beginActivity(
            options: .userInitiatedAllowingIdleSystemSleep,
            reason: "Animating agent activity"
        )
        let timer = Timer(timeInterval: Self.tickInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.now = Date() }
        }
        // Common mode keeps the cats moving while a menu is open or a window is
        // being resized, instead of freezing mid-strike.
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        if let activity {
            ProcessInfo.processInfo.endActivity(activity)
            self.activity = nil
        }
        now = Date()   // one last value so views settle on their resting pose
    }
}
