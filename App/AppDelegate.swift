import AppKit

/// Zitrusscheibe als Template-Icon für die Menüleiste.
func citrusIcon() -> NSImage {
    let size = NSSize(width: 18, height: 18)
    let image = NSImage(size: size, flipped: false) { rect in
        NSColor.black.setStroke()
        NSColor.black.setFill()
        let c = NSPoint(x: rect.midX, y: rect.midY)
        let ring = NSBezierPath(ovalIn: rect.insetBy(dx: 1.2, dy: 1.2))
        ring.lineWidth = 1.4
        ring.stroke()
        let segments = 8
        for i in 0..<segments {
            let mid = CGFloat(i) * 2 * .pi / CGFloat(segments)
            let half = CGFloat.pi / CGFloat(segments) - 0.12
            let slice = NSBezierPath()
            slice.move(to: NSPoint(x: c.x + cos(mid) * 1.6, y: c.y + sin(mid) * 1.6))
            slice.appendArc(withCenter: c, radius: 6.0, startAngle: (mid - half) * 180 / .pi,
                            endAngle: (mid + half) * 180 / .pi)
            slice.close()
            slice.fill()
        }
        return true
    }
    image.isTemplate = true
    return image
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var item: NSStatusItem!
    private let hintItem = NSMenuItem()
    private static let wheels = WheelController()
    private var wheels: WheelController { Self.wheels }

    /// Liest das gespeicherte Apps-Wheel-Kürzel und schaltet Hotkey bzw. Doppeltipp-Erkennung entsprechend.
    static func applyAppsShortcut() {
        GlobalHotKey.shared.unregister()
        DoubleTapDetector.shared.stop()
        let shortcut = AppsShortcut.current
        switch shortcut.kind {
        case .combo: GlobalHotKey.shared.register(keyCode: shortcut.keyCode, modifiers: shortcut.carbonModifiers) { wheels.showAppsByHotKey() }
        case .doubleTap: DoubleTapDetector.shared.start(modifier: shortcut.doubleTapModifier) { wheels.showAppsByHotKey() }
        case .none: break
        }
    }

    func applicationDidFinishLaunching(_ note: Notification) {
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = citrusIcon()
        item.menu = buildStatusMenu()
        NSApp.mainMenu = buildMainMenu()
        wheels.start()
        Self.applyAppsShortcut()
        WatchManager.shared.reload()
        runDemoIfRequested()
        runWindowDemos()
    }

    private func buildStatusMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self
        let ready = NSMenuItem(title: "FileConvert is ready", action: nil, keyEquivalent: "")
        ready.image = NSImage(systemSymbolName: "checkmark.circle", accessibilityDescription: nil)
        ready.isEnabled = false
        menu.addItem(ready)
        hintItem.isEnabled = false
        hintItem.indentationLevel = 1
        menu.addItem(hintItem)
        menu.addItem(.separator())
        let settings = menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settings.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: nil)
        settings.target = self
        menu.addItem(withTitle: "About FileConvert", action: #selector(openAbout), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit FileConvert", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        return menu
    }

    /// Hinweiszeile "⇧: Convert · ⌘: Tools · ^: Actions" nach den gewählten Tasten.
    func menuNeedsUpdate(_ menu: NSMenu) {
        let names: [(WheelKind, String)] = [(.conversion, "Convert"), (.tools, "Tools"), (.actions, "Actions")]
        hintItem.title = names.map { "\($0.0.modifier.symbol): \($0.1)" }.joined(separator: " · ")
    }

    /// App-Menü für ⌘, und ⌘Q, solange ein Fenster der App aktiv ist.
    private func buildMainMenu() -> NSMenu {
        let main = NSMenu()
        let appItem = NSMenuItem()
        main.addItem(appItem)
        let menu = NSMenu()
        menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit FileConvert", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = menu
        return main
    }

    @objc func openSettings() { SettingsWindow.shared.show() }

    @objc func openAbout() {
        UserDefaults.standard.set(SettingsTab.about.rawValue, forKey: "settingsTab")
        SettingsWindow.shared.show()
    }

    /// Erneutes Öffnen der App zeigt die Settings (wie bei Tangerine).
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openSettings()
        return true
    }

    /// Nur zur Sichtprüfung: --demo-wheel conversion|tools|actions DATEI
    private func runDemoIfRequested() {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--demo-wheel"), args.count > i + 2 else { return }
        let kinds: [String: WheelKind] = ["conversion": .conversion, "tools": .tools, "actions": .actions]
        wheels.demo(kinds[args[i + 1]] ?? .tools, file: URL(fileURLWithPath: args[i + 2]))
        if let h = args.firstIndex(of: "--hover"), args.count > h + 1, let n = Int(args[h + 1]) { wheels.demoHover(n) }
    }

    /// Nur zur Sichtprüfung: --demo-organize PDF oder --demo-float DATEI
    private func runWindowDemos() {
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--demo-organize"), args.count > i + 1 {
            OrganizeWindow.show(URL(fileURLWithPath: args[i + 1]))
        }
        if let i = args.firstIndex(of: "--selftest-bgremove"), args.count > i + 1 {
            do {
                let out = try BackgroundRemover.removeBackground(from: URL(fileURLWithPath: args[i + 1]))
                let share = BackgroundRemover.transparentShare(of: out) ?? -1
                print("OUT \(out.path) transparent=\(String(format: "%.2f", share))")
                exit(share > 0.15 && share < 0.95 ? 0 : 1)
            } catch { print("FAIL \(error.localizedDescription)"); exit(1) }
        }
        if let i = args.firstIndex(of: "--demo-compress"), args.count > i + 1 {
            CompressWindow.show(URL(fileURLWithPath: args[i + 1]))
        }
        if let i = args.firstIndex(of: "--demo-pdfedit"), args.count > i + 1 {
            PDFEditWindow.show(URL(fileURLWithPath: args[i + 1]), tool: .redact)
        }
        if args.contains("--selftest-shortcut") { exit(runShortcutSelfTest() ? 0 : 1) }
        if args.contains("--selftest-wheel") { exit(runWheelSelfTest() ? 0 : 1) }
        if let i = args.firstIndex(of: "--demo-apps") { wheels.demo(.apps, file: URL(fileURLWithPath: args.count > i + 1 ? args[i + 1] : "/etc/hosts")) }
        if args.contains("--selftest-pdfedit") { exit(runPDFEditSelfTest() ? 0 : 1) }
        if args.contains("--selftest-annotate") { exit(runAnnotateSelfTest() ? 0 : 1) }
        if let i = args.firstIndex(of: "--demo-annotate"), args.count > i + 1 {
            AnnotateWindow.show(URL(fileURLWithPath: args[i + 1]))
        }
        if args.contains("--selftest-watch") {
            DispatchQueue.global().async { exit(runWatchSelfTest() ? 0 : 1) }
            return
        }
        if args.contains("--selftest-rename") { exit(runRenameSelfTest() ? 0 : 1) }
        if let i = args.firstIndex(of: "--demo-rename"), args.count > i + 1 {
            RenameWindow.show(args[(i + 1)...].filter { !$0.hasPrefix("--") }.map { URL(fileURLWithPath: $0) })
        }
        if args.contains("--demo-hud") {
            ProgressHUD.shared.begin("Converting to DOCX…", total: 3)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { ProgressHUD.shared.advance() }
        }
        if let i = args.firstIndex(of: "--demo-metadata"), args.count > i + 1 {
            MetadataWindow.show([URL(fileURLWithPath: args[i + 1])])
        }
        if let i = args.firstIndex(of: "--selftest-organize"), args.count > i + 1,
           let model = OrganizeModel(url: URL(fileURLWithPath: args[i + 1])) {
            model.move(model.pages[0].id, to: model.pages[model.pages.count - 1].id)   // erste Seite ans Ende
            model.rotate(model.pages[0].id)
            model.toggle(model.pages[1].id)   // zweite Seite abwählen
            model.sameWidth = args.contains("--same-width")
            print(model.save()?.path ?? "FEHLER")
            exit(0)
        }
        if let i = args.firstIndex(of: "--demo-float"), args.count > i + 1 {
            FloatManager.shared.add([URL(fileURLWithPath: args[i + 1])])
            if args.contains("--expanded") { FloatManager.shared.expandLast() }
        }
    }
}
