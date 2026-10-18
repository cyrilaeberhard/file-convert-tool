import AppKit
import Carbon.HIToolbox
import SwiftUI

/// Apps, die im Apps-Wheel erscheinen (Pfade in den Einstellungen gespeichert).
enum AppsStore {
    private static let key = "wheelApps"
    static let maxApps = 9

    static var defaults: [String] {
        ["com.apple.Preview", "com.apple.TextEdit", "com.apple.Safari", "com.apple.mail", "com.apple.Notes"]
            .compactMap { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0)?.path }
    }

    static var paths: [String] {
        get { UserDefaults.standard.stringArray(forKey: key) ?? defaults }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }

    static var apps: [URL] {
        paths.map { URL(fileURLWithPath: $0) }.filter { FileManager.default.fileExists(atPath: $0.path) }.prefix(maxApps).map { $0 }
    }

    static func name(_ url: URL) -> String {
        Bundle(url: url)?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }

    /// Ohne Dateien wird die App nur gestartet, sonst öffnet sie die Dateien.
    static func open(_ files: [URL], with app: URL) {
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        if files.isEmpty { NSWorkspace.shared.openApplication(at: app, configuration: config) }
        else { NSWorkspace.shared.open(files, withApplicationAt: app, configuration: config) }
    }
}

/// Globaler Tastenkürzel über Carbon (braucht keine Bedienungshilfen-Rechte).
final class GlobalHotKey {
    static let shared = GlobalHotKey()
    private var ref: EventHotKeyRef?
    private var handler: EventHandlerRef?
    fileprivate var action: (() -> Void)?

    /// Standard: ⌃⌥Space. Rückgabe 0 = ok.
    @discardableResult
    func register(keyCode: Int = kVK_Space, modifiers: Int = controlKey | optionKey, action: @escaping () -> Void) -> OSStatus {
        unregister()
        self.action = action
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            GlobalHotKey.shared.action?()
            return noErr
        }, 1, &spec, nil, &handler)
        guard status == noErr else { return status }
        let id = EventHotKeyID(signature: OSType(0x46434F4E), id: 1)   // "FCON"
        return RegisterEventHotKey(UInt32(keyCode), UInt32(modifiers), id, GetApplicationEventTarget(), 0, &ref)
    }

    func unregister() {
        if let ref { UnregisterEventHotKey(ref) }
        if let handler { RemoveEventHandler(handler) }
        ref = nil
        handler = nil
        action = nil
    }
}

struct AppsEditorView: View {
    @State private var paths = AppsStore.paths
    let close: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                Text("Apps Wheel").font(.system(size: 18, weight: .semibold))
                HStack {
                    Button(action: close) {
                        Image(systemName: "xmark").font(.system(size: 13, weight: .bold))
                            .frame(width: 34, height: 34).background(Circle().fill(Color.white.opacity(0.16)))
                    }.buttonStyle(.plain)
                    Spacer()
                }
            }
            Text("Hold the Apps modifier while dragging files and drop them on an app to open them there. Up to \(AppsStore.maxApps) apps.")
                .font(.system(size: 12)).foregroundColor(.white.opacity(0.7)).multilineTextAlignment(.center)
            ScrollView {
                VStack(spacing: 6) {
                    ForEach(Array(paths.enumerated()), id: \.element) { index, path in
                        HStack(spacing: 10) {
                            Image(nsImage: NSWorkspace.shared.icon(forFile: path)).resizable().frame(width: 30, height: 30)
                            Text(AppsStore.name(URL(fileURLWithPath: path))).font(.system(size: 14))
                            Spacer()
                            Button { move(index, -1) } label: { Image(systemName: "chevron.up") }.buttonStyle(.plain).disabled(index == 0)
                            Button { move(index, 1) } label: { Image(systemName: "chevron.down") }.buttonStyle(.plain).disabled(index == paths.count - 1)
                            Button { paths.remove(at: index); save() } label: { Image(systemName: "minus.circle") }.buttonStyle(.plain)
                        }
                        .padding(8).background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.08)))
                    }
                }
            }
            HStack {
                Button("Add App…") { add() }.buttonStyle(AccentButton()).disabled(paths.count >= AppsStore.maxApps)
                Button("Reset") { paths = AppsStore.defaults; save() }.buttonStyle(AccentButton())
                Spacer()
            }
        }
        .padding(18)
        .frame(width: 460, height: 520)
        .foregroundColor(.white)
        .focusEffectDisabled()
        .liquidGlass(in: RoundedRectangle(cornerRadius: 32))
    }

    private func save() { AppsStore.paths = paths }

    private func move(_ index: Int, _ delta: Int) {
        let target = index + delta
        guard paths.indices.contains(target) else { return }
        paths.swapAt(index, target)
        save()
    }

    private func add() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.applicationBundle]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = true
        panel.prompt = "Add"
        guard panel.runModal() == .OK else { return }
        for url in panel.urls where !paths.contains(url.path) && paths.count < AppsStore.maxApps { paths.append(url.path) }
        save()
    }
}

enum AppsEditorWindow {
    static func show() { GlassWindow.present(size: NSSize(width: 460, height: 520)) { close in AppsEditorView(close: close) } }
}

/// Lauffähiger Check: `FileConvert --selftest-wheel` (Geometrie, Apps-Liste, Tastenkürzel).
func runWheelSelfTest() -> Bool {
    var failures: [String] = []
    func check(_ ok: Bool, _ what: String) { if !ok { failures.append(what) } }
    let c = WheelGeometry.size / 2, r = (WheelGeometry.inner + WheelGeometry.outer) / 2
    // y nach oben: oben = c + r
    check(WheelGeometry.index(at: CGPoint(x: c, y: c + r), count: 6) == 0, "top is segment 0")
    check(WheelGeometry.index(at: CGPoint(x: c + r, y: c), count: 4) == 1, "right is segment 1 of 4")
    check(WheelGeometry.index(at: CGPoint(x: c, y: c - r), count: 4) == 2, "bottom is segment 2 of 4")
    check(WheelGeometry.index(at: CGPoint(x: c - r, y: c), count: 4) == 3, "left is segment 3 of 4")
    check(WheelGeometry.index(at: CGPoint(x: c, y: c), count: 6) == nil, "center is no segment")
    check(WheelGeometry.index(at: CGPoint(x: c, y: c + WheelGeometry.outer + 60), count: 6) == nil, "far outside is no segment")
    check(WheelGeometry.index(at: CGPoint(x: c, y: c + r), count: 0) == nil, "empty wheel")
    check(WheelKind.allCases.count == 4 && Set(WheelKind.allCases.map(\.defaultModifier)).count == 4, "four wheels, four modifiers")
    check(AppsStore.maxApps >= AppsStore.apps.count, "apps within limit")
    check(WheelItems.items(.apps, for: []).count == AppsStore.apps.count, "apps wheel mirrors store")
    var fired = false
    let status = GlobalHotKey.shared.register(keyCode: kVK_F19, modifiers: controlKey | optionKey | shiftKey) { fired = true }
    check(status == noErr, "hotkey registers (status \(status))")
    _ = fired
    GlobalHotKey.shared.unregister()
    failures.forEach { print("FAIL wheel:", $0) }
    return failures.isEmpty
}
