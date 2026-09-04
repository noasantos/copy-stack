import SwiftUI

/// Cancellable, looping cue timeline for the demo scenes. Cue times from SPEC.md §5.
@MainActor
final class DemoTimeline: ObservableObject {
    enum QuickPasteCue: Equatable {
        case idle, keysDown, open(selected: Int), down(selected: Int), up(selected: Int), returnKey, pasted

        /// Row highlighted in the Quick Paste panel; `nil` means the panel is closed.
        var selectedRow: Int? {
            switch self {
            case .idle, .keysDown, .pasted: return nil
            case .open(let row), .down(let row), .up(let row): return row
            case .returnKey: return 1
            }
        }

        var panelOpen: Bool { selectedRow != nil }
    }

    enum CaptureCue: Equatable {
        case idle, keysDown, crosshair, drag, release, landed

        var dimmed: Bool { self == .crosshair || self == .drag }
        var dragged: Bool { self == .drag || self == .release || self == .landed }
        var landed: Bool { self == .landed }
    }

    enum Key: Hashable { case shift, command, letterV, letterS, up, down, `return` }

    @Published private(set) var quickPaste: QuickPasteCue = .idle
    @Published private(set) var capture: CaptureCue = .idle
    @Published private(set) var pressedKeys: Set<Key> = []

    private var task: Task<Void, Never>?

    /// SPEC §5: 0 idle · 900 keys down · 1150 panel open · 2100/2900 ↓ · 3800 ↑ · 4800 ↩ · 5000 pasted · 7400 reset.
    /// Key caps hold for 250 ms (motion table), so each press schedules its own release.
    func startQuickPaste() {
        run(total: 7400, cues: [
            Cue(0) { $0.reset(); $0.quickPaste = .idle },
            Cue(900) { $0.pressedKeys = [.shift, .command, .letterV] },
            Cue(1150) { $0.pressedKeys = []; $0.quickPaste = .open(selected: 0) },
            Cue(2100) { $0.pressedKeys = [.down]; $0.quickPaste = .down(selected: 1) },
            Cue(2350) { $0.pressedKeys = [] },
            Cue(2900) { $0.pressedKeys = [.down]; $0.quickPaste = .down(selected: 2) },
            Cue(3150) { $0.pressedKeys = [] },
            Cue(3800) { $0.pressedKeys = [.up]; $0.quickPaste = .up(selected: 1) },
            Cue(4050) { $0.pressedKeys = [] },
            Cue(4800) { $0.pressedKeys = [.return]; $0.quickPaste = .returnKey },
            Cue(5000) { $0.quickPaste = .pasted },
            Cue(5050) { $0.pressedKeys = [] }
        ])
    }

    /// SPEC §5: 0 idle · 900 keys down · 1150 crosshair + dim · 1700 drag · 2600 release · 3000 landed · 6600 reset.
    func startCapture() {
        run(total: 6600, cues: [
            Cue(0) { $0.reset(); $0.capture = .idle },
            Cue(900) { $0.pressedKeys = [.shift, .command, .letterS] },
            Cue(1150) { $0.pressedKeys = []; $0.capture = .crosshair },
            Cue(1700) { $0.capture = .drag },
            Cue(2600) { $0.capture = .release },
            Cue(3000) { $0.capture = .landed }
        ])
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    /// Holds the demo on one cue. Used by the previews and snapshots, which need a still frame.
    func freeze(quickPaste: QuickPasteCue = .idle, capture: CaptureCue = .idle, pressedKeys: Set<Key> = []) {
        stop()
        self.quickPaste = quickPaste
        self.capture = capture
        self.pressedKeys = pressedKeys
    }

    private struct Cue {
        let at: Int
        let fire: (DemoTimeline) -> Void
        init(_ at: Int, _ fire: @escaping (DemoTimeline) -> Void) {
            self.at = at
            self.fire = fire
        }
    }

    private func reset() {
        quickPaste = .idle
        capture = .idle
        pressedKeys = []
    }

    private func run(total: Int, cues: [Cue]) {
        stop()
        task = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                var elapsed = 0
                for cue in cues {
                    if cue.at > elapsed {
                        try? await Task.sleep(for: .milliseconds(cue.at - elapsed))
                        elapsed = cue.at
                    }
                    guard !Task.isCancelled, let self else { return }
                    if cue.at == 0 {
                        // The loop reset is instant — never animate the scene back to its start.
                        var transaction = Transaction()
                        transaction.disablesAnimations = true
                        withTransaction(transaction) { cue.fire(self) }
                    } else {
                        cue.fire(self)
                    }
                }
                if total > elapsed {
                    try? await Task.sleep(for: .milliseconds(total - elapsed))
                }
            }
        }
    }
}
