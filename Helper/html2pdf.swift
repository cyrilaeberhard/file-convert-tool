// html2pdf OUT.pdf IN1.html [IN2.html ...]
// Rendert lokale HTML-Dateien (ohne JavaScript) seitenweise zu einem PDF (A4).
import AppKit
import PDFKit
import WebKit

let paper = NSSize(width: 595, height: 842)
let margin: CGFloat = 40

final class Renderer: NSObject, WKNavigationDelegate {
    let window = NSWindow(contentRect: NSRect(origin: .zero, size: paper),
                          styleMask: [.borderless], backing: .buffered, defer: false)
    let web: WKWebView
    let output: URL
    let tmp: URL
    var queue: [URL]
    var parts: [URL] = []

    let readRoot: URL?

    init(output: URL, inputs: [URL], readRoot: URL?) {
        self.readRoot = readRoot
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = false
        web = WKWebView(frame: NSRect(origin: .zero, size: paper), configuration: config)
        self.output = output
        self.queue = inputs
        tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        super.init()
        try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        window.contentView = web
        window.setFrameOrigin(NSPoint(x: -20000, y: -20000))
        window.orderFrontRegardless()
        web.navigationDelegate = self
    }

    func next() {
        guard !queue.isEmpty else { return finish() }
        let url = queue.removeFirst()
        web.loadFileURL(url, allowingReadAccessTo: readRoot ?? url.deletingLastPathComponent())
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        let part = tmp.appendingPathComponent("part-\(parts.count).pdf")
        let info = NSPrintInfo()
        info.paperSize = paper
        info.topMargin = margin; info.bottomMargin = margin
        info.leftMargin = margin; info.rightMargin = margin
        info.jobDisposition = .save
        info.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = part
        let op = webView.printOperation(with: info)
        op.showsPrintPanel = false
        op.showsProgressPanel = false
        op.view?.frame = NSRect(origin: .zero, size: paper)
        parts.append(part)
        op.runModal(for: window, delegate: self,
                    didRun: #selector(printDone(_:success:contextInfo:)), contextInfo: nil)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        fail("Laden fehlgeschlagen: \(error.localizedDescription)")
    }

    @objc func printDone(_ op: NSPrintOperation, success: Bool, contextInfo: UnsafeMutableRawPointer?) {
        success ? next() : fail("Drucken fehlgeschlagen")
    }

    func finish() {
        let doc = PDFDocument()
        for part in parts {
            guard let pdf = PDFDocument(url: part) else { continue }
            for i in 0..<pdf.pageCount {
                if let page = pdf.page(at: i) { doc.insert(page, at: doc.pageCount) }
            }
        }
        try? FileManager.default.removeItem(at: tmp)
        guard doc.pageCount > 0, doc.write(to: output) else { return fail("Keine Seiten erzeugt") }
        exit(0)
    }

    func fail(_ message: String) {
        FileHandle.standardError.write(Data((message + "\n").utf8))
        try? FileManager.default.removeItem(at: tmp)
        exit(1)
    }
}

var args = Array(CommandLine.arguments.dropFirst())
var readRoot: URL?
if args.count >= 2, args[0] == "--root" {
    readRoot = URL(fileURLWithPath: args[1])
    args.removeFirst(2)
}
guard args.count >= 2 else {
    FileHandle.standardError.write(Data("Nutzung: html2pdf [--root DIR] OUT.pdf IN.html...\n".utf8))
    exit(2)
}
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let renderer = Renderer(output: URL(fileURLWithPath: args[0]),
                        inputs: args[1...].map { URL(fileURLWithPath: $0) },
                        readRoot: readRoot)
DispatchQueue.main.async { renderer.next() }
DispatchQueue.main.asyncAfter(deadline: .now() + 300) { renderer.fail("Zeitüberschreitung") }
app.run()
