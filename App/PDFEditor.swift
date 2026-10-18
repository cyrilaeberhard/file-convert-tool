import AppKit
import PDFKit
import SwiftUI

final class RedactAnnotation: PDFAnnotation {
    var isSelected = false

    init(bounds: CGRect) { super.init(bounds: bounds, forType: .square, withProperties: nil) }
    override init(bounds: CGRect, forType type: PDFAnnotationSubtype, withProperties properties: [AnyHashable: Any]?) {
        super.init(bounds: bounds, forType: type, withProperties: properties)
    }
    required init?(coder: NSCoder) { fatalError("nicht benutzt") }

    override func draw(with box: PDFDisplayBox, in context: CGContext) {
        context.saveGState()
        context.setFillColor(CGColor(gray: 0, alpha: 0.85))
        context.fill(bounds)
        if isSelected {
            context.setStrokeColor(NSColor.systemOrange.cgColor)
            context.setLineWidth(2)
            context.stroke(bounds.insetBy(dx: 1, dy: 1))
        }
        context.restoreGState()
    }
}

final class SignatureAnnotation: PDFAnnotation {
    let image: NSImage
    var isSelected = false

    init(bounds: CGRect, image: NSImage) {
        self.image = image
        super.init(bounds: bounds, forType: .stamp, withProperties: nil)
    }
    override init(bounds: CGRect, forType type: PDFAnnotationSubtype, withProperties properties: [AnyHashable: Any]?) {
        image = NSImage()
        super.init(bounds: bounds, forType: type, withProperties: properties)
    }
    required init?(coder: NSCoder) { fatalError("nicht benutzt") }

    override func draw(with box: PDFDisplayBox, in context: CGContext) {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
        context.saveGState()
        context.draw(cg, in: bounds)
        if isSelected {
            context.setStrokeColor(NSColor.systemOrange.cgColor)
            context.setLineWidth(1.5)
            context.setLineDash(phase: 0, lengths: [5, 4])
            context.stroke(bounds.insetBy(dx: -2, dy: -2))
        }
        context.restoreGState()
    }
}

enum EditTool: String { case select, redact, sign }

final class PDFEditModel: ObservableObject {
    let url: URL
    let document: PDFDocument
    @Published var tool: EditTool
    @Published var signature: NSImage? = SignatureStore.image
    @Published var selected: PDFAnnotation?
    @Published var status = ""
    private(set) var added: [(page: PDFPage, annotation: PDFAnnotation)] = []

    init?(url: URL, tool: EditTool) {
        guard let doc = PDFDocument(url: url), doc.pageCount > 0 else { return nil }
        self.url = url
        document = doc
        self.tool = tool
    }

    var editCount: Int { added.count }

    func register(_ annotation: PDFAnnotation, on page: PDFPage) {
        added.append((page, annotation))
        objectWillChange.send()
    }

    func select(_ annotation: PDFAnnotation?) {
        (selected as? RedactAnnotation)?.isSelected = false
        (selected as? SignatureAnnotation)?.isSelected = false
        selected = annotation
        (annotation as? RedactAnnotation)?.isSelected = true
        (annotation as? SignatureAnnotation)?.isSelected = true
    }

    func remove(_ annotation: PDFAnnotation) {
        guard let entry = added.first(where: { $0.annotation === annotation }) else { return }
        entry.page.removeAnnotation(annotation)
        added.removeAll { $0.annotation === annotation }
        if selected === annotation { selected = nil }
        objectWillChange.send()
    }

    func undo() { if let last = added.last { remove(last.annotation) } }

    /// Unterschrift in der Breite des gewählten Elements ändern.
    func resizeSelected(by factor: CGFloat) {
        guard let sig = selected as? SignatureAnnotation else { return }
        let b = sig.bounds, w = b.width * factor, h = b.height * factor
        sig.bounds = CGRect(x: b.midX - w / 2, y: b.midY - h / 2, width: w, height: h)
    }

    func save() -> URL? {
        let reds = added.compactMap { entry -> (page: Int, rect: CGRect)? in
            guard entry.annotation is RedactAnnotation else { return nil }
            return (document.index(for: entry.page), entry.annotation.bounds)
        }
        let sigs = added.compactMap { entry -> PDFEditExporter.Signature? in
            guard let sig = entry.annotation as? SignatureAnnotation,
                  let cg = sig.image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
            return .init(page: document.index(for: entry.page), rect: sig.bounds, image: cg)
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

/// PDFView, die je nach Werkzeug Rechtecke aufzieht, Unterschriften setzt oder Elemente verschiebt.
final class EditorPDFView: PDFView {
    weak var model: PDFEditModel?
    private var live: RedactAnnotation?
    private var livePage: PDFPage?
    private var origin = CGPoint.zero
    private var moving: PDFAnnotation?
    private var grab = CGPoint.zero

    override var acceptsFirstResponder: Bool { true }

    private func pagePoint(_ event: NSEvent) -> (PDFPage, CGPoint)? {
        let viewPoint = convert(event.locationInWindow, from: nil)
        guard let page = page(for: viewPoint, nearest: true) else { return nil }
        return (page, convert(viewPoint, to: page))
    }

    private func ours(_ page: PDFPage, _ point: CGPoint) -> PDFAnnotation? {
        page.annotations.last { ($0 is RedactAnnotation || $0 is SignatureAnnotation) && $0.bounds.insetBy(dx: -3, dy: -3).contains(point) }
    }

    private func redraw(_ page: PDFPage) { setNeedsDisplay(convert(page.bounds(for: displayBox), from: page)) }

    override func mouseDown(with event: NSEvent) {
        guard let model, let (page, point) = pagePoint(event) else { return super.mouseDown(with: event) }
        window?.makeFirstResponder(self)
        // Vorhandene Elemente lassen sich mit jedem Werkzeug anfassen und verschieben.
        if let hit = ours(page, point) {
            model.select(hit)
            moving = hit
            grab = CGPoint(x: point.x - hit.bounds.minX, y: point.y - hit.bounds.minY)
            redraw(page)
            return
        }
        model.select(nil)
        switch model.tool {
        case .redact:
            let annotation = RedactAnnotation(bounds: CGRect(origin: point, size: .zero))
            page.addAnnotation(annotation)
            live = annotation; livePage = page; origin = point
        case .sign:
            place(on: page, at: point)
        case .select:
            super.mouseDown(with: event)
        }
        redraw(page)
    }

    override func mouseDragged(with event: NSEvent) {
        if let moving, let (page, point) = pagePoint(event) {
            moving.bounds = CGRect(x: point.x - grab.x, y: point.y - grab.y, width: moving.bounds.width, height: moving.bounds.height)
            redraw(page)
        } else if let live, let livePage {
            let point = convert(convert(event.locationInWindow, from: nil), to: livePage)
            live.bounds = CGRect(x: min(origin.x, point.x), y: min(origin.y, point.y), width: abs(point.x - origin.x), height: abs(point.y - origin.y))
            redraw(livePage)
        } else { super.mouseDragged(with: event) }
    }

    override func mouseUp(with event: NSEvent) {
        moving = nil
        if let live, let livePage {
            if live.bounds.width < 6 || live.bounds.height < 6 { livePage.removeAnnotation(live) }
            else { model?.register(live, on: livePage); model?.select(live) }
            redraw(livePage)
        }
        live = nil; livePage = nil
        super.mouseUp(with: event)
    }

    override func keyDown(with event: NSEvent) {
        if [51, 117].contains(event.keyCode), let selected = model?.selected, let page = selected.page {
            model?.remove(selected)
            redraw(page)
        } else { super.keyDown(with: event) }
    }

    func place(on page: PDFPage, at point: CGPoint) {
        guard let model else { return }
        guard let image = model.signature else {
            SignatureWindow.show { [weak self, weak model] image in
                model?.signature = image
                self?.place(on: page, at: point)
            }
            return
        }
        let width = min(190, page.bounds(for: .cropBox).width * 0.3)
        let height = width * image.size.height / max(1, image.size.width)
        let annotation = SignatureAnnotation(bounds: CGRect(x: point.x - width / 2, y: point.y - height / 2, width: width, height: height), image: image)
        page.addAnnotation(annotation)
        model.register(annotation, on: page)
        model.select(annotation)
        redraw(page)
    }
}

struct PDFViewHost: NSViewRepresentable {
    let model: PDFEditModel

    func makeNSView(context: Context) -> EditorPDFView {
        let view = EditorPDFView()
        view.model = model
        view.document = model.document
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displaysPageBreaks = true
        view.backgroundColor = NSColor(white: 0.12, alpha: 1)
        return view
    }

    func updateNSView(_ view: EditorPDFView, context: Context) { view.needsDisplay = true }
}

struct PDFEditView: View {
    @ObservedObject var model: PDFEditModel
    let close: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                VStack(spacing: 2) {
                    Text("Sign & Redact").font(.system(size: 18, weight: .semibold))
                    Text(model.url.lastPathComponent).font(.system(size: 12)).foregroundColor(.white.opacity(0.65)).lineLimit(1)
                }
                HStack {
                    Button(action: close) {
                        Image(systemName: "xmark").font(.system(size: 13, weight: .bold))
                            .frame(width: 34, height: 34).background(Circle().fill(Color.white.opacity(0.16)))
                    }.buttonStyle(.plain)
                    Spacer()
                }
            }.padding(14)
            toolbar.padding(.horizontal, 18).padding(.bottom, 10)
            PDFViewHost(model: model)
                .clipShape(RoundedRectangle(cornerRadius: 14)).padding(.horizontal, 18)
            Divider().padding(14)
            HStack {
                Text(hint).font(.system(size: 12)).foregroundColor(.white.opacity(0.65))
                Spacer()
                Button(action: save) {
                    Text(model.added.contains { $0.annotation is RedactAnnotation } ? "Save Redacted PDF" : "Save PDF")
                        .font(.system(size: 15, weight: .semibold)).foregroundColor(.white)
                        .padding(.horizontal, 22).padding(.vertical, 9)
                        .background(RoundedRectangle(cornerRadius: 10).fill(accent))
                }.buttonStyle(.plain).disabled(model.editCount == 0).opacity(model.editCount == 0 ? 0.4 : 1)
            }.padding(.horizontal, 18).padding(.bottom, 14)
        }
        .frame(width: 860, height: 740)
        .foregroundColor(.white)
        .focusEffectDisabled()
        .liquidGlass(in: RoundedRectangle(cornerRadius: 36))
    }

    private var hint: String {
        switch model.tool {
        case .redact: return "Drag over text or images to black them out. Redacted pages are flattened, the hidden text is gone for good."
        case .sign: return "Click on the page to place your signature. Drag to move, ⌫ to delete."
        case .select: return "Select text or drag existing marks."
        }
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            toolButton(.select, "cursorarrow", "Select")
            toolButton(.redact, "rectangle.fill", "Redact")
            toolButton(.sign, "signature", "Sign")
            Divider().frame(height: 22)
            Button("Signature…") { SignatureWindow.show { model.signature = $0; model.tool = .sign } }.buttonStyle(AccentButton())
            Button { model.resizeSelected(by: 1.15) } label: { Image(systemName: "plus.magnifyingglass") }
                .buttonStyle(.plain).disabled(!(model.selected is SignatureAnnotation)).help("Larger signature")
            Button { model.resizeSelected(by: 1 / 1.15) } label: { Image(systemName: "minus.magnifyingglass") }
                .buttonStyle(.plain).disabled(!(model.selected is SignatureAnnotation)).help("Smaller signature")
            Spacer()
            Button { model.undo() } label: { Label("Undo", systemImage: "arrow.uturn.backward") }
                .buttonStyle(.plain).disabled(model.editCount == 0).opacity(model.editCount == 0 ? 0.4 : 1)
        }
    }

    private func toolButton(_ tool: EditTool, _ symbol: String, _ title: String) -> some View {
        Button { model.tool = tool } label: {
            Label(title, systemImage: symbol).font(.system(size: 13, weight: .medium))
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(RoundedRectangle(cornerRadius: 8).fill(model.tool == tool ? accent.opacity(0.7) : Color.white.opacity(0.1)))
        }.buttonStyle(.plain)
    }

    private func save() {
        guard let out = model.save() else {
            let alert = NSAlert()
            alert.messageText = "Speichern fehlgeschlagen"
            alert.runModal()
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([out])
        close()
    }
}

enum PDFEditWindow {
    static func show(_ url: URL, tool: EditTool) {
        guard let model = PDFEditModel(url: url, tool: tool) else {
            let alert = NSAlert()
            alert.messageText = "PDF konnte nicht geöffnet werden"
            alert.runModal()
            return
        }
        GlassWindow.present(size: NSSize(width: 860, height: 740)) { close in PDFEditView(model: model, close: close) }
    }
}
