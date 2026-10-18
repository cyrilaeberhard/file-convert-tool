import AppKit
import PDFKit
import SwiftUI

/// Seiten eines PDFs ordnen, drehen und optional auf gleiche Breite bringen.
final class OrganizeModel: ObservableObject {
    struct Page: Identifiable, Equatable {
        let id: Int          // Seitennummer im Original (0-basiert)
        var rotation = 0     // zusätzliche Drehung in Grad
        var included = true  // abgewählte Seiten kommen nicht ins Ergebnis
    }

    let url: URL
    let doc: PDFDocument
    @Published var pages: [Page]
    @Published var sameWidth = false
    @Published var dragging: Int?

    init?(url: URL) {
        guard let doc = PDFDocument(url: url), doc.pageCount > 0 else { return nil }
        self.url = url
        self.doc = doc
        pages = (0..<doc.pageCount).map { Page(id: $0) }
    }

    var original: [Page] { (0..<doc.pageCount).map { Page(id: $0) } }
    var changed: Bool { pages != original }

    func reset() { pages = original }

    func toggle(_ id: Int) {
        pages = pages.map { $0.id == id ? Page(id: id, rotation: $0.rotation, included: !$0.included) : $0 }
    }

    /// Anzeigenummer: zählt nur die gewählten Seiten.
    func number(of page: Page) -> Int? {
        guard page.included, let index = pages.filter(\.included).firstIndex(where: { $0.id == page.id }) else { return nil }
        return index + 1
    }

    var includedCount: Int { pages.filter(\.included).count }

    func rotate(_ id: Int) {
        pages = pages.map { $0.id == id ? Page(id: id, rotation: ($0.rotation + 90) % 360, included: $0.included) : $0 }
    }

    /// Verschiebt die Seite `id` an die Stelle von `target` (für Drag & Drop).
    func move(_ id: Int, to target: Int) {
        guard id != target, let from = pages.firstIndex(where: { $0.id == id }),
              let to = pages.firstIndex(where: { $0.id == target }) else { return }
        var next = pages
        next.insert(next.remove(at: from), at: to)
        pages = next
    }

    /// Seite mit der gewünschten Zusatzdrehung (Kopie, das Original bleibt unverändert).
    func page(_ p: Page) -> PDFPage? {
        guard let copy = doc.page(at: p.id)?.copy() as? PDFPage else { return nil }
        copy.rotation = (copy.rotation + p.rotation) % 360
        return copy
    }

    private func size(of page: PDFPage) -> CGSize {
        let box = page.bounds(for: .cropBox)
        return page.rotation % 180 == 0 ? box.size : CGSize(width: box.height, height: box.width)
    }

    private func outputURL() -> URL {
        let dir = url.deletingLastPathComponent(), base = url.deletingPathExtension().lastPathComponent
        var out = dir.appendingPathComponent("\(base)_organized.pdf"), n = 2
        while FileManager.default.fileExists(atPath: out.path) {
            out = dir.appendingPathComponent("\(base)_organized-\(n).pdf")
            n += 1
        }
        return out
    }

    func save() -> URL? {
        let result = PDFDocument()
        for p in pages where p.included {
            guard let page = page(p) else { continue }
            result.insert(page, at: result.pageCount)
        }
        let out = outputURL()
        if sameWidth, let scaled = scaledData(result) {
            return (try? scaled.write(to: out)) != nil ? out : nil
        }
        return result.write(to: out) ? out : nil
    }

    /// Alle Seiten proportional auf die Breite der schmalsten Seite skalieren.
    private func scaledData(_ document: PDFDocument) -> Data? {
        let pages = (0..<document.pageCount).compactMap { document.page(at: $0) }
        guard let target = pages.map({ size(of: $0).width }).min() else { return nil }
        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data as CFMutableData) else { return nil }
        var first = CGRect(x: 0, y: 0, width: target, height: 100)
        guard let ctx = CGContext(consumer: consumer, mediaBox: &first, nil) else { return nil }
        for page in pages {
            let dims = size(of: page)
            let scale = target / dims.width
            var box = CGRect(x: 0, y: 0, width: target, height: dims.height * scale)
            let info = [kCGPDFContextMediaBox as String: Data(bytes: &box, count: MemoryLayout<CGRect>.size)] as CFDictionary
            ctx.beginPDFPage(info)
            ctx.scaleBy(x: scale, y: scale)
            page.draw(with: .cropBox, to: ctx)
            ctx.endPDFPage()
        }
        ctx.closePDF()
        return data as Data
    }
}

private extension Data {
    func write(to url: URL) throws { try (self as NSData).write(to: url, options: .atomic) }
}

struct PageThumb: View {
    let model: OrganizeModel
    let page: OrganizeModel.Page
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image { Image(nsImage: image).resizable().aspectRatio(contentMode: .fit) }
            else { Color(white: 0.95) }
        }
        .onAppear(perform: render)
        .onChange(of: page.rotation) { _, _ in render() }
    }

    private func render() {
        let model = model, page = page
        DispatchQueue.global(qos: .userInitiated).async {
            let thumb = model.page(page)?.thumbnail(of: CGSize(width: 320, height: 440), for: .cropBox)
            DispatchQueue.main.async { image = thumb }
        }
    }
}

struct PageDropDelegate: DropDelegate {
    let target: Int
    let model: OrganizeModel

    func dropEntered(info: DropInfo) {
        if let id = model.dragging { withAnimation(.easeInOut(duration: 0.18)) { model.move(id, to: target) } }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }
    func performDrop(info: DropInfo) -> Bool { model.dragging = nil; return true }
}

struct OrganizeView: View {
    @ObservedObject var model: OrganizeModel
    let close: () -> Void
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 14), count: 4)

    var body: some View {
        VStack(spacing: 0) {
            header
            HStack {
                Text(model.includedCount == model.pages.count ? "\(model.pages.count) pages" : "\(model.includedCount) of \(model.pages.count) pages").font(.system(size: 15, weight: .medium)).foregroundColor(.white.opacity(0.9))
                Spacer()
                Button("Reset Order") { withAnimation { model.reset() } }
                    .buttonStyle(.plain).foregroundColor(.white.opacity(model.changed ? 0.9 : 0.35))
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.12)))
                    .disabled(!model.changed)
            }.padding(.horizontal, 18).padding(.bottom, 10)
            ScrollView {
                LazyVGrid(columns: columns, spacing: 14) {
                    ForEach(Array(model.pages.enumerated()), id: \.element.id) { index, page in cell(model.number(of: page), page) }
                }.padding(.horizontal, 18).padding(.vertical, 4)
            }
            Divider().padding(.horizontal, 12)
            VStack(alignment: .leading, spacing: 8) {
                Toggle("Make all pages the same width", isOn: $model.sameWidth).toggleStyle(.checkbox)
                Text("Pages are scaled proportionally to match the narrowest page; their heights may still differ.")
                    .font(.system(size: 12)).foregroundColor(.white.opacity(0.7))
            }.padding(.horizontal, 18).padding(.vertical, 10).frame(maxWidth: .infinity, alignment: .leading)
            Divider().padding(.horizontal, 12)
            HStack {
                Spacer()
                Button(action: save) {
                    Text("Save Organized PDF").font(.system(size: 15, weight: .semibold)).foregroundColor(.white)
                        .padding(.horizontal, 18).padding(.vertical, 9)
                        .background(RoundedRectangle(cornerRadius: 10).fill(accent))
                }.buttonStyle(.plain).disabled(model.includedCount == 0).opacity(model.includedCount == 0 ? 0.4 : 1)
            }.padding(14)
        }
        .frame(width: 570, height: 630)
        .foregroundColor(.white)
        .focusEffectDisabled()
        .liquidGlass(in: RoundedRectangle(cornerRadius: 36))
    }

    private var header: some View {
        ZStack {
            Text("Organize PDF").font(.system(size: 18, weight: .semibold))
            HStack {
                Button(action: close) {
                    Image(systemName: "xmark").font(.system(size: 13, weight: .bold))
                        .frame(width: 34, height: 34).background(Circle().fill(Color.white.opacity(0.16)))
                }.buttonStyle(.plain)
                Spacer()
            }
        }.padding(14)
    }

    private func cell(_ number: Int?, _ page: OrganizeModel.Page) -> some View {
        ZStack {
            PageThumb(model: model, page: page)
                .frame(height: 160)
                .padding(4)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color(white: 0.95)))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            VStack {
                HStack {
                    ZStack {
                        Circle().fill(number == nil ? Color.black.opacity(0.45) : accent)
                        if let number { Text("\(number)").font(.system(size: 14, weight: .bold)).foregroundColor(.white) }
                        else { Image(systemName: "minus").font(.system(size: 12, weight: .bold)).foregroundColor(.white) }
                    }.frame(width: 28, height: 28)
                    Spacer()
                    Button { model.rotate(page.id) } label: {
                        Image(systemName: "rotate.right").font(.system(size: 13, weight: .semibold)).foregroundColor(.white)
                            .frame(width: 28, height: 28).background(Circle().fill(Color.black.opacity(0.55)))
                    }.buttonStyle(.plain)
                }
                Spacer()
            }.padding(6)
        }
        .opacity(model.dragging == page.id ? 0.4 : (page.included ? 1 : 0.4))
        .onTapGesture { withAnimation(.easeOut(duration: 0.12)) { model.toggle(page.id) } }
        .onDrag {
            model.dragging = page.id
            return NSItemProvider(object: "\(page.id)" as NSString)
        }
        .onDrop(of: [.text], delegate: PageDropDelegate(target: page.id, model: model))
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

/// Rahmenloses Fenster mit Liquid-Glass-Inhalt; im oberen Streifen verschiebbar.
final class GlassWindow: NSWindow {
    private static var open: [GlassWindow] = []

    override var canBecomeKey: Bool { true }

    override func sendEvent(_ event: NSEvent) {
        let point = event.locationInWindow
        if event.type == .leftMouseDown, point.y > frame.height - 56, point.x > 64 {
            performDrag(with: event)
            return
        }
        super.sendEvent(event)
    }

    /// Öffnet ein Glas-Fenster; `content` bekommt eine Close-Funktion.
    static func present<Content: View>(size: NSSize, @ViewBuilder content: ((@escaping () -> Void)) -> Content) {
        let window = GlassWindow(contentRect: NSRect(origin: .zero, size: size),
                                 styleMask: [.borderless, .fullSizeContentView], backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.isReleasedWhenClosed = false
        let close = { [weak window] in
            guard let window else { return }
            window.close()
            open.removeAll { $0 === window }
        }
        let host = NSHostingView(rootView: content(close))
        host.wantsLayer = true
        host.layer?.cornerRadius = 36
        host.layer?.masksToBounds = true
        window.contentView = host
        window.center()
        open.append(window)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}

enum OrganizeWindow {
    static func show(_ url: URL) {
        guard let model = OrganizeModel(url: url) else {
            let alert = NSAlert()
            alert.messageText = "PDF konnte nicht geöffnet werden"
            alert.runModal()
            return
        }
        GlassWindow.present(size: NSSize(width: 570, height: 630)) { close in OrganizeView(model: model, close: close) }
    }
}
