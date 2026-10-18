import AppKit
import Foundation

enum WheelKind: CaseIterable {
    case conversion, tools, actions, apps

    var prefKey: String {
        switch self {
        case .conversion: return "conversionWheel"
        case .tools: return "toolsWheel"
        case .actions: return "actionsWheel"
        case .apps: return "appsWheel"
        }
    }

    var defaultModifier: DragModifier {
        switch self {
        case .conversion: return .shift
        case .tools: return .command
        case .actions: return .control
        case .apps: return .option
        }
    }

    var modifier: DragModifier {
        DragModifier(rawValue: UserDefaults.standard.string(forKey: prefKey) ?? "") ?? defaultModifier
    }
}

/// Führt Backend-Aufrufe aus und meldet das Ergebnis (Ton, Finder, Fehlerdialog).
enum Jobs {
    static func each(_ urls: [URL], title: String = "Working…", info: Bool = false,
                     _ args: @escaping (URL) -> [String]) {
        ProgressHUD.shared.begin(title, total: urls.count)
        DispatchQueue.global().async {
            var results: [(Bool, String)] = []
            for url in urls {
                results.append(Backend.run(args(url)))
                DispatchQueue.main.async { ProgressHUD.shared.advance() }
            }
            DispatchQueue.main.async {
                ProgressHUD.shared.end()
                finish(results, info: info)
            }
        }
    }

    /// Freisteller (läuft in Swift, nicht im Python-Backend).
    static func removeBackground(_ urls: [URL]) {
        ProgressHUD.shared.begin("Removing background…", total: urls.count)
        DispatchQueue.global().async {
            var outputs: [URL] = [], failure: String?
            for url in urls {
                do { outputs.append(try BackgroundRemover.removeBackground(from: url)) }
                catch { failure = "\(url.lastPathComponent): \(error.localizedDescription)" }
                DispatchQueue.main.async { ProgressHUD.shared.advance() }
            }
            DispatchQueue.main.async {
                ProgressHUD.shared.end()
                if let failure, outputs.isEmpty { finish([(false, failure)], info: false) }
                else { finish([(true, outputs.map(\.path).joined(separator: "\n"))], info: false) }
            }
        }
    }

    static func once(_ args: [String], title: String = "Working…") {
        ProgressHUD.shared.begin(title, total: 1)
        DispatchQueue.global().async {
            let result = Backend.run(args)
            DispatchQueue.main.async {
                ProgressHUD.shared.end()
                finish([result], info: false)
            }
        }
    }

    private static func finish(_ results: [(Bool, String)], info: Bool) {
        if let failed = results.first(where: { !$0.0 }) {
            if UserDefaults.standard.object(forKey: "feedback") as? Bool ?? true { NSSound(named: "Basso")?.play() }
            let alert = NSAlert()
            alert.messageText = "Fehlgeschlagen"
            alert.informativeText = failed.1
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
            return
        }
        if UserDefaults.standard.object(forKey: "feedback") as? Bool ?? true { NSSound(named: "Glass")?.play() }
        if info {
            let alert = NSAlert()
            alert.messageText = results.map { $0.1 }.joined(separator: "\n")
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
            return
        }
        let outputs = results.compactMap { $0.1.split(separator: "\n").last }
            .map { URL(fileURLWithPath: String($0)) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
        if !outputs.isEmpty { NSWorkspace.shared.activateFileViewerSelecting(outputs) }
    }
}

enum WheelItems {
    private static func ext(_ url: URL) -> String { Caps.normalize(url.pathExtension) }

    static func centerLabel(_ urls: [URL]) -> String {
        if urls.isEmpty { return "Apps" }
        guard urls.count == 1 else { return "\(urls.count) files" }
        let size = (try? urls[0].resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        return ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
    }

    static func items(_ kind: WheelKind, for urls: [URL]) -> [WheelItem] {
        switch kind {
        case .conversion: return conversion(urls)
        case .tools: return tools(urls)
        case .actions: return actions(urls)
        case .apps: return apps()
        }
    }

    // MARK: Conversion

    static func convertArgs(_ url: URL, to target: String) -> [String] {
        let keep = FormatPrefs.preserveMetadata(for: target)
        return ["convert", url.path, target, "-q", String(FormatPrefs.quality(for: target))]
            + (keep ? [] : ["--no-metadata"])
    }

    private static func conversion(_ urls: [URL]) -> [WheelItem] {
        guard let first = urls.first else { return [] }
        return Caps.wheel(of: ext(first)).prefix(9).map { target in
            WheelItem(title: target.uppercased(), symbol: nil) { files in
                Jobs.each(files, title: "Converting to \(target.uppercased())…") { convertArgs($0, to: target) }
            }
        }
    }

    // MARK: Tools

    private static func compressArgs(_ url: URL) -> [String] {
        let source = ext(url)
        let strong = (UserDefaults.standard.string(forKey: "fmt.\(source).compression") ?? "balanced") == "strong"
        if source == "pdf" { return ["pdf-compress", url.path, "-l", strong ? "low" : "medium"] }
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        let targetMB = max(0.01, Double(size) / 1_048_576 * (strong ? 0.35 : 0.6))
        return ["compress", url.path, String(targetMB)]
    }

    /// Ein Treffer öffnet die Vorschau, mehrere werden mit den Format-Einstellungen direkt komprimiert.
    private static func compressItem() -> WheelItem {
        WheelItem(title: "Compress", symbol: "arrow.down.right.and.arrow.up.left") { files in
            if files.count == 1, CompressWindow.show(files[0]) { return }
            Jobs.each(files, title: "Compressing…", compressArgs)
        }
    }

    private static func tool(_ title: String, _ symbol: String, info: Bool = false,
                             _ args: @escaping (URL) -> [String]) -> WheelItem {
        WheelItem(title: title, symbol: symbol) { Jobs.each($0, title: "\(title)…", info: info, args) }
    }

    private static func tools(_ urls: [URL]) -> [WheelItem] {
        guard let first = urls.first else { return [] }
        let kind = Caps.group(of: ext(first))?.title
        var items: [WheelItem] = []
        switch kind {
        case "Images", "Video":
            items = [compressItem(),
                     WheelItem(title: "Metadata", symbol: "tag") { MetadataWindow.show($0) }]
            if kind == "Images" {
                items.append(WheelItem(title: "Read QR", symbol: "qrcode.viewfinder") { QRReader.readAndShow($0) })
                items.append(WheelItem(title: "Annotate", symbol: "pencil.and.scribble") { AnnotateWindow.show($0[0]) })
                items.append(WheelItem(title: "Remove BG", symbol: "person.crop.rectangle") { Jobs.removeBackground($0) })
            }
        case "Audio":
            items = [tool("Mono", "speaker") { ["channels", $0.path, "mono"] },
                     tool("Waveform", "waveform") { ["waveform", $0.path] },
                     tool("Silence", "speaker.slash", info: true) { ["silence", $0.path] },
                     WheelItem(title: "Metadata", symbol: "tag") { MetadataWindow.show($0) }]
        case "Documents" where ext(first) == "pdf":
            items = [compressItem(),
                     WheelItem(title: "Metadata", symbol: "tag") { MetadataWindow.show($0) },
                     tool("Split", "rectangle.split.2x1") { ["pdf-split", $0.path] },
                     WheelItem(title: "Organize", symbol: "square.grid.2x2") { OrganizeWindow.show($0[0]) },
                     WheelItem(title: "Read QR", symbol: "qrcode.viewfinder") { QRReader.readAndShow($0) },
                     WheelItem(title: "Sign", symbol: "signature") { PDFEditWindow.show($0[0], tool: .sign) },
                     WheelItem(title: "Redact", symbol: "rectangle.fill") { PDFEditWindow.show($0[0], tool: .redact) }]
            if urls.count > 1 {
                items.append(WheelItem(title: "Merge", symbol: "square.on.square") { files in
                    let out = files[0].deletingLastPathComponent().appendingPathComponent("merged.pdf").path
                    Jobs.once(["pdf-merge", out] + files.map { $0.path }, title: "Merging PDFs…")
                })
            }
        case "Documents":
            items = [tool("To PDF", "doc.richtext") { ["convert", $0.path, "pdf"] }]
        case "Archives":
            items = [tool("Unpack", "archivebox") { ["unpack", $0.path] }]
        default:
            break
        }
        items.append(WheelItem(title: "Rename", symbol: "textformat.abc") { RenameWindow.show($0) })
        if ext(first) != "zip", ext(first) != "pdf" {
            items.append(WheelItem(title: "Zip", symbol: "doc.zipper") { Jobs.once(["zip"] + $0.map { $0.path }, title: "Zipping…") })
        }
        if urls.count > 1, kind == "Images" {
            items.append(WheelItem(title: "Collage", symbol: "square.grid.2x2") { Jobs.once(["collage"] + $0.map { $0.path }, title: "Creating collage…") })
        }
        return items
    }

    // MARK: Apps

    private static func apps() -> [WheelItem] {
        AppsStore.apps.map { app in
            let icon = NSWorkspace.shared.icon(forFile: app.path)
            return WheelItem(title: AppsStore.name(app), symbol: nil, icon: icon) { AppsStore.open($0, with: app) }
        }
    }

    // MARK: Actions (Reihenfolge wie im Original, im Uhrzeigersinn ab oben)

    private static func actions(_ urls: [URL]) -> [WheelItem] {
        [
            WheelItem(title: "AirDrop", symbol: "dot.radiowaves.left.and.right") { NativeActions.airDrop($0) },
            WheelItem(title: "Float", symbol: "pin.fill") { FloatManager.shared.add($0) },
            WheelItem(title: "Copy", symbol: "doc.on.doc") { NativeActions.copyFiles($0) },
            WheelItem(title: "Move", symbol: "folder") { NativeActions.move($0) },
            WheelItem(title: "Copy path", symbol: "doc.text") { NativeActions.copyPaths($0) },
            WheelItem(title: "Terminal", symbol: "terminal") { NativeActions.openTerminal($0) },
        ]
    }
}

