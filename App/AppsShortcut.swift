import AppKit
import Carbon.HIToolbox
import SwiftUI

/// Tastenkürzel des Apps-Wheels: Tastenkombination, Doppeltipp einer Modifier-Taste oder keins.
struct AppsShortcut: Codable, Equatable {
    enum Kind: String, Codable { case combo, doubleTap, none }

    var kind: Kind
    var keyCode = 0
    var carbonModifiers = 0       // controlKey | optionKey | ...
    var keyLabel = ""             // z. B. "Space", "A"
    var modifier = DragModifier.option.rawValue

    static let standard = AppsShortcut(kind: .combo, keyCode: kVK_Space, carbonModifiers: controlKey | optionKey, keyLabel: "Space")
    static let off = AppsShortcut(kind: .none)

    var doubleTapModifier: DragModifier { DragModifier(rawValue: modifier) ?? .option }

    var label: String {
        switch kind {
        case .none: return "Not set"
        case .doubleTap: return "Double-tap \(doubleTapModifier.symbol) \(doubleTapModifier.label.dropFirst(3))"
        case .combo:
            let symbols = [(controlKey, "⌃"), (optionKey, "⌥"), (shiftKey, "⇧"), (cmdKey, "⌘")]
            return symbols.filter { carbonModifiers & $0.0 != 0 }.map(\.1).joined() + keyLabel
        }
    }

    static func carbon(from flags: NSEvent.ModifierFlags) -> Int {
        var result = 0
        if flags.contains(.control) { result |= controlKey }
        if flags.contains(.option) { result |= optionKey }
        if flags.contains(.shift) { result |= shiftKey }
        if flags.contains(.command) { result |= cmdKey }
        return result
    }

    static func label(for event: NSEvent) -> String {
        switch Int(event.keyCode) {
        case kVK_Space: return "Space"
        case kVK_Return: return "Return"
        case kVK_Tab: return "Tab"
        case kVK_LeftArrow: return "←"
        case kVK_RightArrow: return "→"
        case kVK_UpArrow: return "↑"
        case kVK_DownArrow: return "↓"
        case kVK_F1...kVK_F20 where event.charactersIgnoringModifiers?.isEmpty ?? true: return "F\(event.keyCode)"
        default: return (event.charactersIgnoringModifiers ?? "?").uppercased()
        }
    }

    static var current: AppsShortcut {
        get {
            if let data = UserDefaults.standard.data(forKey: "appsShortcut"),
               let decoded = try? JSONDecoder().decode(AppsShortcut.self, from: data) { return decoded }
            // Übernahme der alten Ein/Aus-Einstellung
            return UserDefaults.standard.object(forKey: "appsHotKey") as? Bool == false ? .off : .standard
        }
        set {
            UserDefaults.standard.set(try? JSONEncoder().encode(newValue), forKey: "appsShortcut")
            AppDelegate.applyAppsShortcut()
        }
    }
}

/// Zustandsmaschine für "zweimal kurz tippen": rein und mit expliziten Zeitstempeln, damit sie testbar ist.
struct DoubleTapMachine {
    var maxHold = 0.30      // so lange darf ein Tipp dauern
    var maxGap = 0.40       // so viel Zeit zwischen zwei Tipps
    private var wasDown = false
    private var pressStart: Double?
    private var lastTapEnd: Double?
    private var spoiled = false

    /// `down`: genau die Ziel-Taste ist allein gedrückt. `invalid`: etwas anderes ist gedrückt (Taste, Maus, andere Modifier).
    mutating func feed(down: Bool, invalid: Bool, at time: Double) -> Bool {
        defer { wasDown = down }
        if invalid {
            spoiled = true
            pressStart = nil
            lastTapEnd = nil
            return false
        }
        if !down && !wasDown { spoiled = false }
        if let last = lastTapEnd, time - last > maxGap { lastTapEnd = nil }
        if down && !wasDown && !spoiled { pressStart = time }
        if !down && wasDown, let start = pressStart {
            pressStart = nil
            guard time - start <= maxHold else { lastTapEnd = nil; return false }
            if let last = lastTapEnd, start - last <= maxGap {
                lastTapEnd = nil
                return true
            }
            lastTapEnd = time
        }
        return false
    }
}

/// Fragt die Modifier-Tasten per Polling ab (braucht keine Bedienungshilfen-Rechte).
final class DoubleTapDetector {
    static let shared = DoubleTapDetector()
    private var timer: Timer?
    private var machine = DoubleTapMachine()
    private var target = NSEvent.ModifierFlags.option
    private var action: (() -> Void)?

    func start(modifier: DragModifier, action: @escaping () -> Void) {
        stop()
        target = modifier.flag
        self.action = action
        machine = DoubleTapMachine()
        timer = Timer.scheduledTimer(withTimeInterval: 0.015, repeats: true) { [weak self] _ in self?.poll() }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        action = nil
    }

    /// Ist eine normale Taste gedrückt? Die Modifier-Tasten selbst (Tastencodes 54-63) zählen nicht,
    /// sonst wäre bei gedrücktem ⌘ immer "eine Taste gedrückt".
    static func anyNonModifierKey(_ isDown: (CGKeyCode) -> Bool) -> Bool {
        (0..<128).contains { !(54...63).contains($0) && isDown(CGKeyCode($0)) }
    }

    private static func anyKeyDown() -> Bool {
        anyNonModifierKey { CGEventSource.keyState(.combinedSessionState, key: $0) }
    }

    private func poll() {
        let flags = NSEvent.modifierFlags.intersection(DragModifier.mask)
        let down = flags == target
        let invalid = (!flags.isEmpty && !down) || NSEvent.pressedMouseButtons != 0 || (down && Self.anyKeyDown())
        if machine.feed(down: down, invalid: invalid, at: ProcessInfo.processInfo.systemUptime) { action?() }
    }
}

/// Feld, das ein Tastenkürzel aufnimmt: Kombination drücken oder eine Modifier-Taste doppelt tippen.
struct ShortcutRecorder: View {
    @State private var shortcut = AppsShortcut.current
    @State private var recording = false
    @State private var monitor: Any?
    @State private var machines: [(DragModifier, DoubleTapMachine)] = DragModifier.allCases.map { ($0, DoubleTapMachine()) }

    var body: some View {
        HStack(spacing: 8) {
            Button(recording ? "Press keys or double-tap a modifier…" : shortcut.label) { recording ? stop() : start() }
                .buttonStyle(.plain)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 8).fill(recording ? accent.opacity(0.35) : Color.primary.opacity(0.1)))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(recording ? accent : .clear, lineWidth: 1.5))
            if shortcut != .standard { Button { set(.standard) } label: { Image(systemName: "arrow.counterclockwise") }.buttonStyle(.plain).help("Reset to ⌃⌥Space") }
            if shortcut.kind != .none { Button { set(.off) } label: { Image(systemName: "xmark.circle") }.buttonStyle(.plain).help("Clear") }
        }
        .onDisappear(perform: stop)
    }

    private func set(_ value: AppsShortcut) {
        shortcut = value
        AppsShortcut.current = value
        stop()
    }

    private func start() {
        recording = true
        machines = DragModifier.allCases.map { ($0, DoubleTapMachine()) }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            if event.type == .keyDown {
                if event.keyCode == UInt16(kVK_Escape) { stop(); return nil }
                let flags = event.modifierFlags.intersection(DragModifier.mask)
                let carbon = AppsShortcut.carbon(from: flags)
                let functionKey = (kVK_F1...kVK_F20).contains(Int(event.keyCode))
                guard carbon != 0 || functionKey else { return nil }
                set(AppsShortcut(kind: .combo, keyCode: Int(event.keyCode), carbonModifiers: carbon, keyLabel: AppsShortcut.label(for: event)))
                return nil
            }
            let flags = event.modifierFlags.intersection(DragModifier.mask)
            for index in machines.indices {
                let modifier = machines[index].0
                let hit = machines[index].1.feed(down: flags == modifier.flag, invalid: !flags.isEmpty && flags != modifier.flag, at: event.timestamp)
                if hit { set(AppsShortcut(kind: .doubleTap, modifier: modifier.rawValue)); return nil }
            }
            return event
        }
    }

    private func stop() {
        recording = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}

/// Prüft die Doppeltipp-Logik mit festen Zeitstempeln: `FileConvert --selftest-shortcut`.
func runShortcutSelfTest() -> Bool {
    var failures: [String] = []
    func run(_ steps: [(Bool, Bool, Double)]) -> Bool {
        var m = DoubleTapMachine()
        return steps.contains { m.feed(down: $0.0, invalid: $0.1, at: $0.2) }
    }
    // zwei kurze Tipps: runter/rauf, runter/rauf
    check(run([(true, false, 0.00), (false, false, 0.10), (true, false, 0.25), (false, false, 0.35)]), "double tap fires", &failures)
    // zu langsam zwischen den Tipps
    check(!run([(true, false, 0.00), (false, false, 0.10), (true, false, 0.90), (false, false, 1.00)]), "slow second tap does not fire", &failures)
    // erster Tipp zu lang (gehalten)
    check(!run([(true, false, 0.00), (false, false, 0.60), (true, false, 0.70), (false, false, 0.80)]), "long hold is no tap", &failures)
    // nur ein Tipp
    check(!run([(true, false, 0.00), (false, false, 0.10)]), "single tap does not fire", &failures)
    // andere Taste gedrückt zwischen den Tipps
    check(!run([(true, false, 0.00), (false, false, 0.10), (false, true, 0.15), (true, false, 0.20), (false, false, 0.30)]), "other key cancels", &failures)
    // Maus gedrückt (Drag) während des zweiten Drückens
    check(!run([(true, false, 0.00), (false, false, 0.10), (true, true, 0.20), (false, false, 0.30)]), "mouse press cancels", &failures)
    // dreimal tippen feuert genau einmal pro Paar
    var m = DoubleTapMachine()
    var fires = 0
    for (down, t) in [(true, 0.0), (false, 0.1), (true, 0.2), (false, 0.3), (true, 0.4), (false, 0.5)] where m.feed(down: down, invalid: false, at: t) { fires += 1 }
    check(fires == 1, "three taps fire once (got \(fires))", &failures)
    // Modifier-Tastencodes dürfen nicht als "andere Taste" gelten (war der Fehler bei Doppeltipp auf ⌘)
    check(!DoubleTapDetector.anyNonModifierKey { $0 == 55 || $0 == 54 || $0 == 58 || $0 == 59 || $0 == 56 }, "modifier keycodes are ignored", &failures)
    check(DoubleTapDetector.anyNonModifierKey { $0 == 0 }, "letter key counts", &failures)
    // Speichern und Beschriften
    check(AppsShortcut.standard.label == "⌃⌥Space", "standard label \(AppsShortcut.standard.label)", &failures)
    let encoded = try? JSONEncoder().encode(AppsShortcut(kind: .doubleTap, modifier: DragModifier.command.rawValue))
    check(encoded.flatMap { try? JSONDecoder().decode(AppsShortcut.self, from: $0) }?.doubleTapModifier == .command, "codable roundtrip", &failures)
    check(AppsShortcut.off.label == "Not set", "off label", &failures)
    failures.forEach { print("FAIL shortcut:", $0) }
    return failures.isEmpty
}

private func check(_ ok: Bool, _ what: String, _ failures: inout [String]) { if !ok { failures.append(what) } }
