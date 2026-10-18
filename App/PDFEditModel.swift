import AppKit
import PDFKit

enum EditTool: String { case select, redact, sign }

/// Ein gesetztes Element (Schwärzung oder Unterschrift); `rect` liegt in Seitenkoordinaten.
final class EditItem {
    enum Kind { case redact, signature(NSImage) }
    let kind: Kind
    let page: PDFPage
    var rect: CGRect

    init(kind: Kind, page: PDFPage, rect: CGRect) {
        self.kind = kind
        self.page = page
        self.rect = rect
    }

    var isSignature: Bool { if case .signature = kind { return true } else { return false } }
}

final class PDFEditModel: ObservableObject {
    let url: URL
    let document: PDFDocument
    @Published var tool: EditTool
    @Published var signature: NSImage? = SignatureStore.image
    @Published var selected: EditItem?
    @Published var status = ""
    private(set) var items: [EditItem] = []
    let overlays = NSMapTable<PDFPage, PageOverlay>.weakToWeakObjects()
    private var history: [Action] = []

    private enum Action {
        case add(EditItem)
        case delete(EditItem)
        case change(EditItem, CGRect)
    }

    init?(url: URL, tool: EditTool) {
        guard let doc = PDFDocument(url: url), doc.pageCount > 0 else { return nil }
        self.url = url
        document = doc
        self.tool = tool
    }

    var editCount: Int { items.count }
    var canUndo: Bool { !history.isEmpty }
    var hasRedaction: Bool { items.contains { !$0.isSignature } }

    func items(on page: PDFPage) -> [EditItem] { items.filter { $0.page === page } }

    func refresh(_ page: PDFPage) { overlays.object(forKey: page)?.needsDisplay = true }

    func add(_ item: EditItem) {
        items.append(item)
        history.append(.add(item))
        select(item)
        refresh(item.page)
        objectWillChange.send()
    }

    func select(_ item: EditItem?) {
        let old = selected
        selected = item
        if let old { refresh(old.page) }
        if let item { refresh(item.page) }
    }

    /// Verschieben oder Skalieren als rückgängig machbaren Schritt festhalten.
    func recordChange(of item: EditItem, from old: CGRect) {
        guard item.rect != old else { return }
        history.append(.change(item, old))
        objectWillChange.send()
    }

    /// Löschen (⌫); lässt sich mit Undo zurückholen.
    func remove(_ item: EditItem) {
        guard detach(item) else { return }
        history.append(.delete(item))
        objectWillChange.send()
    }

    @discardableResult
    private func detach(_ item: EditItem) -> Bool {
        guard items.contains(where: { $0 === item }) else { return false }
        items.removeAll { $0 === item }
        if selected === item { selected = nil }
        refresh(item.page)
        return true
    }

    func undo() {
        guard let last = history.popLast() else { return }
        switch last {
        case .add(let item):
            detach(item)
        case .delete(let item):
            items.append(item)
            select(item)
        case .change(let item, let old):
            item.rect = old
            refresh(item.page)
        }
        objectWillChange.send()
    }

    /// Unterschrift um einen Faktor vergrössern oder verkleinern (Mitte bleibt).
    func resizeSelected(by factor: CGFloat) {
        guard let item = selected, item.isSignature else { return }
        let b = item.rect, w = b.width * factor, h = b.height * factor
        item.rect = CGRect(x: b.midX - w / 2, y: b.midY - h / 2, width: w, height: h)
        recordChange(of: item, from: b)
        refresh(item.page)
    }

    func save() -> URL? {
        let reds = items.compactMap { item -> (page: Int, rect: CGRect)? in
            item.isSignature ? nil : (document.index(for: item.page), item.rect)
        }
        let sigs = items.compactMap { item -> PDFEditExporter.Signature? in
            guard case .signature(let image) = item.kind,
                  let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
            return .init(page: document.index(for: item.page), rect: item.rect, image: cg)
        }
        let suffix = reds.isEmpty ? "signed" : "redacted"
        let dir = url.deletingLastPathComponent(), base = url.deletingPathExtension().lastPathComponent
        var out = dir.appendingPathComponent("\(base)_\(suffix).pdf"), n = 2
        while FileManager.default.fileExists(atPath: out.path) {
            out = dir.appendingPathComponent("\(base)_\(suffix)-\(n).pdf")
            n += 1
        }
        return PDFEditExporter.export(document, redactions: reds, signatures: sigs, to: out) ? out : nil
    }
}
