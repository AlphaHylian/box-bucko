import Foundation

/// A small, self-contained Pomodoro timer. Not persisted across launches --
/// same as `idleSpeechTimer`/`cursorFollowTimer` elsewhere in the app, a
/// pomodoro session is a "while I'm actively using my Mac" thing, not
/// something worth resurrecting after a reboot.
final class PomodoroTimer {
    enum Phase: Equatable {
        case idle
        case work
        case shortBreak
        case longBreak
    }

    private(set) var phase: Phase = .idle
    private(set) var remainingSeconds: Int = 0
    private(set) var isPaused = false
    /// Completed work sessions in the current cycle; every 4th break is long.
    private(set) var completedWorkSessions = 0

    var workMinutes: Int {
        get { Preferences.shared.pomodoroWorkMinutes }
        set { Preferences.shared.pomodoroWorkMinutes = newValue }
    }
    var breakMinutes: Int {
        get { Preferences.shared.pomodoroBreakMinutes }
        set { Preferences.shared.pomodoroBreakMinutes = newValue }
    }
    private let longBreakMinutes = 15
    private let sessionsPerLongBreak = 4

    /// Fired every second while running (including paused ticks are skipped).
    var onTick: (() -> Void)?
    /// Fired whenever the phase changes -- including to `.idle` when stopped.
    var onPhaseChange: ((Phase) -> Void)?

    private var timer: Timer?

    var isRunning: Bool { phase != .idle }

    func start() {
        guard phase == .idle else { return }
        completedWorkSessions = 0
        beginPhase(.work)
    }

    func pause() {
        guard isRunning, !isPaused else { return }
        isPaused = true
        onTick?()
    }

    func resume() {
        guard isRunning, isPaused else { return }
        isPaused = false
        onTick?()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        phase = .idle
        remainingSeconds = 0
        isPaused = false
        onPhaseChange?(.idle)
    }

    /// Skips straight to the next phase (work -> break, break -> work).
    func skip() {
        guard isRunning else { return }
        advance()
    }

    private func beginPhase(_ newPhase: Phase) {
        phase = newPhase
        isPaused = false
        let minutes: Int
        switch newPhase {
        case .idle: minutes = 0
        case .work: minutes = workMinutes
        case .shortBreak: minutes = breakMinutes
        case .longBreak: minutes = longBreakMinutes
        }
        remainingSeconds = max(1, minutes) * 60
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
        onPhaseChange?(newPhase)
    }

    private func tick() {
        guard !isPaused else { return }
        remainingSeconds -= 1
        if remainingSeconds <= 0 {
            advance()
        } else {
            onTick?()
        }
    }

    private func advance() {
        switch phase {
        case .idle:
            return
        case .work:
            completedWorkSessions += 1
            let isLongBreak = completedWorkSessions % sessionsPerLongBreak == 0
            beginPhase(isLongBreak ? .longBreak : .shortBreak)
        case .shortBreak, .longBreak:
            beginPhase(.work)
        }
    }

    /// "24:35" style countdown string.
    var formattedRemaining: String {
        let m = remainingSeconds / 60
        let s = remainingSeconds % 60
        return String(format: "%d:%02d", m, s)
    }
}
