import AppKit
import PDFKit
import SwiftUI
import Vision

private func alert(_ title: String, _ text: String = "") {
    let alert = NSAlert()
    alert.messageText = title
    alert.informativeText = text
    NSApp.activate(ignoringOtherApps: true)
    alert.runModal()
}

enum QRReader {
    private static func images(for url: URL) -> [CGImage] {
        if url.pathExtension.lowercased() == "pdf" {
            guard let doc = PDFDocument(url: url) else { return [] }
            return (0..<min(doc.pageCount, 20)).compactMap { index in
                doc.page(at: index)?.thumbnail(of: CGSize(width: 1600, height: 1600), for: .mediaBox)
                    .cgImage(forProposedRect: nil, context: nil, hints: nil)
            }
        }
        guard let image = NSImage(contentsOf: url) else { return [] }
        return [image.cgImage(forProposedRect: nil, context: nil, hints: nil)].compactMap { $0 }
    }

    private static func decode(_ image: CGImage) -> [String] {
        let request = VNDetectBarcodesRequest()
        request.symbologies = [.qr]
        try? VNImageRequestHandler(cgImage: image).perform([request])
        return (request.results ?? []).compactMap { $0.payloadStringValue }
    }

    /// Liest QR-Codes aus Bildern und PDFs, kopiert das Ergebnis in die Zwischenablage.
    static func readAndShow(_ urls: [URL]) {
        DispatchQueue.global().async {
            let codes = urls.flatMap { images(for: $0).flatMap(decode) }
            DispatchQueue.main.async {
                guard !codes.isEmpty else { return alert("Kein QR-Code gefunden") }
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(codes.joined(separator: "\n"), forType: .string)
                alert("QR-Code gelesen (in Zwischenablage)", codes.joined(separator: "\n"))
            }
        }
    }
}

enum NativeActions {
    static func copyPaths(_ urls: [URL]) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(urls.map { $0.path }.joined(separator: "\n"), forType: .string)
    }

    static func copyFiles(_ urls: [URL]) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects(urls as [NSURL])
    }

    static func airDrop(_ urls: [URL]) {
        NSSharingService(named: .sendViaAirDrop)?.perform(withItems: urls)
    }

    static func openTerminal(_ urls: [URL]) {
        let name = UserDefaults.standard.string(forKey: "terminalApp") ?? "Terminal"
        let id = name == "iTerm" ? "com.googlecode.iterm2" : "com.apple.Terminal"
        guard let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else {
            return alert("\(name) nicht gefunden")
        }
        let folder = urls[0].hasDirectoryPath ? urls[0] : urls[0].deletingLastPathComponent()
        NSWorkspace.shared.open([folder], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
    }

    /// Fragt nach einem Zielordner und verschiebt die Dateien dorthin (ohne zu überschreiben).
    static func move(_ urls: [URL]) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Move Here"
        panel.message = "Choose a destination folder for \(urls.count) item\(urls.count == 1 ? "" : "s")."
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let folder = panel.url else { return }
        for url in urls {
            var target = folder.appendingPathComponent(url.lastPathComponent)
            var n = 2
            while FileManager.default.fileExists(atPath: target.path) {
                let name = url.deletingPathExtension().lastPathComponent
                target = folder.appendingPathComponent("\(name)-\(n)").appendingPathExtension(url.pathExtension)
                n += 1
            }
            do { try FileManager.default.moveItem(at: url, to: target) }
            catch { return alert("Verschieben fehlgeschlagen", error.localizedDescription) }
        }
    }
}
