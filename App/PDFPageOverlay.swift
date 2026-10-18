import AppKit
import PDFKit
import SwiftUI

/// Überlagerung pro PDF-Seite: zeichnet Schwärzungen und Unterschriften und behandelt Maus und Tasten.
final class PageOverlay: NSView {
    private enum Drag {
        case move(EditItem, grab: CGPoint, start: CGRect)
        case resize(EditItem, start: CGRect)
        case draw(origin: CGPoint)
    }

    let page: PDFPage
    private unowned let model: PDFEditModel
    weak var pdfView: PDFView?
    private var drag: Drag?
    private var live: EditItem?
    private let handleSize: CGFloat = 14

    init(page: PDFPage, model: PDFEditModel) {
        self.page = page
        self.model = model
        super.init(frame: .zero)
    }
    required init?(coder: NSCoder) { fatalError("nicht benutzt") }

    override var acceptsFirstResponder: Bool { true }

    // MARK: Koordinaten

    private func viewRect(_ item: EditItem) -> CGRect { pdfView?.convert(item.rect, from: page) ?? .zero }

    private func handleRect(_ viewRect: CGRect) -> CGRect {
        let lowerY = (pdfView?.isFlipped ?? false) ? viewRect.maxY - handleSize : viewRect.minY
        return CGRect(x: viewRect.maxX - handleSize, y: lowerY, width: handleSize, height: handleSize)
    }

    private func viewPoint(_ event: NSEvent) -> CGPoint { pdfView?.convert(event.locationInWindow, from: nil) ?? .zero }

    private func pagePoint(_ viewPoint: CGPoint) -> CGPoint { pdfView?.convert(viewPoint, to: page) ?? .zero }

    private func item(atView point: CGPoint) -> EditItem? {
        model.items(on: page).last { viewRect($0).insetBy(dx: -4, dy: -4).contains(point) }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let hit = super.hitTest(point) else { return nil }
        if model.tool != .select { return hit }
        guard let pdfView else { return nil }
        let viewPt = pdfView.convert(convert(point, from: superview), from: self)
        if let selected = model.selected, selected.page === page, handleRect(viewRect(selected)).contains(viewPt) { return hit }
        return item(atView: viewPt) != nil ? hit : nil
    }

    // MARK: Zeichnen

    override func draw(_ dirtyRect: NSRect) {
        guard let pdfView, let context = NSGraphicsContext.current?.cgContext else { return }
        for item in model.items(on: page) + (live.map { [$0] } ?? []) {
            let rect = convert(viewRect(item), from: pdfView)
            switch item.kind {
            case .redact:
                context.setFillColor(CGColor(gray: 0, alpha: 0.85))
                context.fill(rect)
            case .signature(let image):
                image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
            }
            guard item === model.selected else { continue }
            NSColor.systemOrange.setStroke()
            let outline = NSBezierPath(rect: rect.insetBy(dx: -2, dy: -2))
            outline.lineWidth = 1.5
            if item.isSignature { outline.setLineDash([5, 4], count: 2, phase: 0) }
            outline.stroke()
            NSColor.systemOrange.setFill()
            NSBezierPath(ovalIn: convert(handleRect(viewRect(item)), from: pdfView)).fill()
        }
    }

    // MARK: Maus

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let viewPt = viewPoint(event), point = pagePoint(viewPt)
        if let selected = model.selected, selected.page === page, handleRect(viewRect(selected)).contains(viewPt) {
            drag = .resize(selected, start: selected.rect)
            return
        }
        if let hit = item(atView: viewPt) {
            model.select(hit)
            drag = .move(hit, grab: CGPoint(x: point.x - hit.rect.minX, y: point.y - hit.rect.minY), start: hit.rect)
            return
        }
        model.select(nil)
        switch model.tool {
        case .redact:
            live = EditItem(kind: .redact, page: page, rect: CGRect(origin: point, size: .zero))
            drag = .draw(origin: point)
        case .sign: place(at: point)
        case .select: break
        }
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        let point = pagePoint(viewPoint(event))
        switch drag {
        case .move(let item, let grab, _):
            item.rect = CGRect(x: point.x - grab.x, y: point.y - grab.y, width: item.rect.width, height: item.rect.height)
        case .resize(let item, let start):
            let width = max(24, point.x - start.minX)
            let height = item.isSignature ? width * start.height / max(1, start.width) : max(8, start.maxY - point.y)
            item.rect = CGRect(x: start.minX, y: start.maxY - height, width: width, height: height)
        case .draw(let origin):
            live?.rect = CGRect(x: min(origin.x, point.x), y: min(origin.y, point.y), width: abs(point.x - origin.x), height: abs(point.y - origin.y))
        case nil: return
        }
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        switch drag {
        case .move(let item, _, let start), .resize(let item, let start): model.recordChange(of: item, from: start)
        case .draw:
            if let live, live.rect.width >= 6, live.rect.height >= 6 { model.add(live) }
        case nil: break
        }
        drag = nil
        live = nil
        needsDisplay = true
    }

    override func keyDown(with event: NSEvent) {
        if [51, 117].contains(event.keyCode), let selected = model.selected { model.remove(selected) }
        else if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers == "z" { model.undo() }
        else { super.keyDown(with: event) }
    }

    private func place(at point: CGPoint) {
        guard let image = model.signature else {
            SignatureWindow.show { [weak self] image in
                self?.model.signature = image
                self?.place(at: point)
            }
            return
        }
        let width = min(190, page.bounds(for: .cropBox).width * 0.3)
        let height = width * image.size.height / max(1, image.size.width)
        model.add(EditItem(kind: .signature(image), page: page,
                           rect: CGRect(x: point.x - width / 2, y: point.y - height / 2, width: width, height: height)))
    }
}

struct PDFViewHost: NSViewRepresentable {
    let model: PDFEditModel

    final class Coordinator: NSObject, PDFPageOverlayViewProvider {
        let model: PDFEditModel
        init(model: PDFEditModel) { self.model = model }

        func pdfView(_ view: PDFView, overlayViewFor page: PDFPage) -> NSView? {
            let overlay = model.overlays.object(forKey: page) ?? PageOverlay(page: page, model: model)
            overlay.pdfView = view
            model.overlays.setObject(overlay, forKey: page)
            return overlay
        }

        func pdfView(_ pdfView: PDFView, willEndDisplayingOverlayView overlayView: NSView, for page: PDFPage) {
            model.overlays.removeObject(forKey: page)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.pageOverlayViewProvider = context.coordinator
        view.document = model.document
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displaysPageBreaks = true
        view.backgroundColor = NSColor(white: 0.12, alpha: 1)
        return view
    }

    func updateNSView(_ view: PDFView, context: Context) {}
}
