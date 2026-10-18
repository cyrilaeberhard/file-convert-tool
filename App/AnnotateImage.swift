import AppKit
import CoreImage
import SwiftUI

enum AnnotationTool: String, CaseIterable, Identifiable {
    case pen, arrow, rect, ellipse, highlight, text, blur
    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .pen: return "pencil.tip"
        case .arrow: return "arrow.up.right"
        case .rect: return "rectangle"
        case .ellipse: return "circle"
        case .highlight: return "highlighter"
        case .text: return "textformat"
        case .blur: return "square.dashed.inset.filled"
        }
    }
}

/// Eine Markierung; Punkte liegen in Bildkoordinaten mit Ursprung oben links.
struct Mark: Identifiable {
    let id = UUID()
    var tool: AnnotationTool
    var points: [CGPoint]
    var color: NSColor
    var width: CGFloat
    var text = ""

    var rect: CGRect {
        guard let a = points.first, let b = points.last else { return .zero }
        return CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
    }
}

/// Zeichnet Markierungen mit CoreGraphics; dieselbe Funktion dient Vorschau und Export.
enum AnnotateRenderer {
    /// Zeichnet `mark` in einen Kontext mit Ursprung unten links und der Höhe `height` des Bildes.
    static func draw(_ mark: Mark, in ctx: CGContext, height: CGFloat, source: CGImage?) {
        func p(_ point: CGPoint) -> CGPoint { CGPoint(x: point.x, y: height - point.y) }
        let flipped = CGRect(x: mark.rect.minX, y: height - mark.rect.maxY, width: mark.rect.width, height: mark.rect.height)
        ctx.saveGState()
        defer { ctx.restoreGState() }
        ctx.setStrokeColor(mark.color.cgColor)
        ctx.setFillColor(mark.color.cgColor)
        ctx.setLineWidth(mark.width)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        switch mark.tool {
        case .pen:
            guard let first = mark.points.first else { return }
            ctx.move(to: p(first))
            mark.points.dropFirst().forEach { ctx.addLine(to: p($0)) }
            ctx.strokePath()
        case .rect: ctx.stroke(flipped)
        case .ellipse: ctx.strokeEllipse(in: flipped)
        case .highlight:
            ctx.setFillColor(mark.color.withAlphaComponent(0.35).cgColor)
            ctx.fill(flipped)
        case .arrow:
            guard let a = mark.points.first, let b = mark.points.last, hypot(b.x - a.x, b.y - a.y) > 2 else { return }
            let start = p(a), end = p(b)
            let angle = atan2(end.y - start.y, end.x - start.x)
            let head = max(14, mark.width * 4.5)
            ctx.move(to: start)
            ctx.addLine(to: end)
            ctx.strokePath()
            ctx.move(to: end)
            ctx.addLine(to: CGPoint(x: end.x - head * cos(angle - .pi / 6), y: end.y - head * sin(angle - .pi / 6)))
            ctx.addLine(to: CGPoint(x: end.x - head * cos(angle + .pi / 6), y: end.y - head * sin(angle + .pi / 6)))
            ctx.closePath()
            ctx.fillPath()
        case .text:
            guard let at = mark.points.first, !mark.text.isEmpty else { return }
            let font = NSFont.systemFont(ofSize: max(18, mark.width * 6), weight: .semibold)
            let string = NSAttributedString(string: mark.text, attributes: [.font: font, .foregroundColor: mark.color])
            let origin = p(at)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
            string.draw(at: CGPoint(x: origin.x, y: origin.y - font.ascender))
            NSGraphicsContext.restoreGraphicsState()
        case .blur:
            guard let source, flipped.width > 2, flipped.height > 2 else { return }
            let scale = CGFloat(source.height) / height
            let crop = CGRect(x: flipped.minX * scale, y: flipped.minY * scale, width: flipped.width * scale, height: flipped.height * scale)
            let image = CIImage(cgImage: source).cropped(to: crop)
            let filter = CIFilter(name: "CIPixellate")
            filter?.setValue(image, forKey: kCIInputImageKey)
            filter?.setValue(max(8, min(crop.width, crop.height) / 12), forKey: kCIInputScaleKey)
            if let out = filter?.outputImage?.cropped(to: crop), let cg = CIContext().createCGImage(out, from: crop) {
                ctx.draw(cg, in: flipped)
            }
        }
    }

    /// Bild mit allen Markierungen (Pixelgröße wie das Original).
    static func render(_ source: CGImage, marks: [Mark]) -> CGImage? {
        let w = source.width, h = source.height
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.draw(source, in: CGRect(x: 0, y: 0, width: w, height: h))
        marks.forEach { draw($0, in: ctx, height: CGFloat(h), source: source) }
        return ctx.makeImage()
    }
}

final class AnnotateModel: ObservableObject {
    let url: URL
    let source: CGImage
    @Published var marks: [Mark] = []
    @Published var live: Mark?
    @Published var tool = AnnotationTool.arrow
    @Published var color = NSColor.systemRed
    @Published var width: CGFloat = 5
    @Published var rendered: NSImage

    init?(url: URL) {
        guard let image = NSImage(contentsOf: url), let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        self.url = url
        source = cg
        rendered = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }

    func commit(_ mark: Mark) {
        marks.append(mark)
        refresh()
    }

    func undo() {
        guard !marks.isEmpty else { return }
        marks.removeLast()
        refresh()
    }

    private func refresh() {
        guard let cg = AnnotateRenderer.render(source, marks: marks) else { return }
        rendered = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }

    func save() -> URL? {
        guard let cg = AnnotateRenderer.render(source, marks: marks) else { return nil }
        let ext = ["jpg", "jpeg"].contains(url.pathExtension.lowercased()) ? "jpg" : "png"
        let rep = NSBitmapImageRep(cgImage: cg)
        guard let data = ext == "jpg" ? rep.representation(using: .jpeg, properties: [.compressionFactor: 0.92])
                                      : rep.representation(using: .png, properties: [:]) else { return nil }
        let dir = url.deletingLastPathComponent(), base = url.deletingPathExtension().lastPathComponent
        var out = dir.appendingPathComponent("\(base)_annotated.\(ext)"), n = 2
        while FileManager.default.fileExists(atPath: out.path) {
            out = dir.appendingPathComponent("\(base)_annotated-\(n).\(ext)")
            n += 1
        }
        return (try? data.write(to: out)) != nil ? out : nil
    }
}

struct AnnotateView: View {
    @ObservedObject var model: AnnotateModel
    let close: () -> Void
    private let colors: [NSColor] = [.systemRed, .systemOrange, .systemYellow, .systemGreen, .systemBlue, .black, .white]

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                VStack(spacing: 2) {
                    Text("Annotate").font(.system(size: 18, weight: .semibold))
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
            canvas.padding(.horizontal, 18)
            Divider().padding(14)
            HStack {
                Button { model.undo() } label: { Label("Undo", systemImage: "arrow.uturn.backward") }
                    .buttonStyle(.plain).disabled(model.marks.isEmpty).opacity(model.marks.isEmpty ? 0.4 : 1)
                Spacer()
                Button(action: save) {
                    Text("Save Annotated").font(.system(size: 15, weight: .semibold)).foregroundColor(.white)
                        .padding(.horizontal, 22).padding(.vertical, 9)
                        .background(RoundedRectangle(cornerRadius: 10).fill(accent))
                }.buttonStyle(.plain)
            }.padding(.horizontal, 18).padding(.bottom, 14)
        }
        .frame(width: 780, height: 660)
        .foregroundColor(.white)
        .focusEffectDisabled()
        .liquidGlass(in: RoundedRectangle(cornerRadius: 36))
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            ForEach(AnnotationTool.allCases) { tool in
                Button { model.tool = tool } label: {
                    Image(systemName: tool.symbol).font(.system(size: 14, weight: .medium)).frame(width: 34, height: 30)
                        .background(RoundedRectangle(cornerRadius: 8).fill(model.tool == tool ? accent.opacity(0.7) : Color.white.opacity(0.1)))
                }.buttonStyle(.plain).help(tool.rawValue.capitalized)
            }
            Divider().frame(height: 22)
            ForEach(colors, id: \.self) { color in
                Button { model.color = color } label: {
                    Circle().fill(Color(nsColor: color)).frame(width: 20, height: 20)
                        .overlay(Circle().stroke(Color.white.opacity(model.color == color ? 1 : 0.25), lineWidth: model.color == color ? 2.5 : 1))
                }.buttonStyle(.plain)
            }
            Divider().frame(height: 22)
            Slider(value: $model.width, in: 2...16).frame(width: 90).tint(accent)
        }
    }

    private var canvas: some View {
        GeometryReader { geo in
            let size = CGSize(width: model.source.width, height: model.source.height)
            let scale = min(geo.size.width / size.width, geo.size.height / size.height)
            let shown = CGSize(width: size.width * scale, height: size.height * scale)
            let origin = CGPoint(x: (geo.size.width - shown.width) / 2, y: (geo.size.height - shown.height) / 2)
            ZStack {
                RoundedRectangle(cornerRadius: 14).fill(Color.black.opacity(0.25))
                Image(nsImage: model.rendered).resizable().frame(width: shown.width, height: shown.height)
                    .position(x: geo.size.width / 2, y: geo.size.height / 2)
                Canvas { context, _ in
                    guard let live = model.live else { return }
                    context.withCGContext { cg in
                        cg.translateBy(x: origin.x, y: origin.y + shown.height)
                        cg.scaleBy(x: scale, y: -scale)
                        AnnotateRenderer.draw(live, in: cg, height: size.height, source: nil)
                        if live.tool == .blur {   // Vorschau der Pixelung: gestrichelter Rahmen
                            cg.setStrokeColor(NSColor.white.cgColor)
                            cg.setLineDash(phase: 0, lengths: [8, 6])
                            cg.stroke(CGRect(x: live.rect.minX, y: size.height - live.rect.maxY, width: live.rect.width, height: live.rect.height))
                        }
                    }
                }
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { value in
                    let point = CGPoint(x: (value.location.x - origin.x) / scale, y: (value.location.y - origin.y) / scale)
                    let clamped = CGPoint(x: min(max(point.x, 0), size.width), y: min(max(point.y, 0), size.height))
                    if model.live == nil {
                        model.live = Mark(tool: model.tool, points: [clamped, clamped], color: model.color, width: model.width / max(scale, 0.1) * 0.6 + model.width * 0.4)
                    } else if model.tool == .pen { model.live?.points.append(clamped) }
                    else { model.live?.points[1] = clamped }
                }
                .onEnded { _ in
                    guard var mark = model.live else { return }
                    model.live = nil
                    if mark.tool == .text {
                        guard let text = askText() else { return }
                        mark.text = text
                    }
                    model.commit(mark)
                })
        }.frame(height: 450)
    }

    private func askText() -> String? {
        let alert = NSAlert()
        alert.messageText = "Text"
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        alert.accessoryView = field
        alert.addButton(withTitle: "Add")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        return alert.runModal() == .alertFirstButtonReturn && !field.stringValue.isEmpty ? field.stringValue : nil
    }

    private func save() {
        guard let out = model.save() else { return }
        NSWorkspace.shared.activateFileViewerSelecting([out])
        close()
    }
}

enum AnnotateWindow {
    static func show(_ url: URL) {
        guard let model = AnnotateModel(url: url) else {
            let alert = NSAlert()
            alert.messageText = "Bild konnte nicht geöffnet werden"
            alert.runModal()
            return
        }
        GlassWindow.present(size: NSSize(width: 780, height: 660)) { close in AnnotateView(model: model, close: close) }
    }
}

/// Lauffähiger Check: `FileConvert --selftest-annotate`.
func runAnnotateSelfTest() -> Bool {
    let w = 200, h = 100
    guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                              space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
    ctx.setFillColor(gray: 1, alpha: 1); ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
    for x in stride(from: 100, to: 140, by: 4) {          // Streifenmuster rechts, damit die Pixelung etwas ändert
        ctx.setFillColor(gray: x % 8 == 0 ? 0 : 1, alpha: 1); ctx.fill(CGRect(x: x, y: 0, width: 2, height: h))
    }
    guard let source = ctx.makeImage() else { return false }
    func pixel(_ image: CGImage, _ x: Int, _ yTop: Int) -> [UInt8] {
        guard let data = image.dataProvider?.data, let b = CFDataGetBytePtr(data) else { return [] }
        let o = yTop * image.bytesPerRow + x * (image.bitsPerPixel / 8)
        return [b[o], b[o + 1], b[o + 2]]
    }
    var failures: [String] = []
    let red = Mark(tool: .rect, points: [CGPoint(x: 10, y: 10), CGPoint(x: 60, y: 50)], color: .red, width: 4)
    let fill = Mark(tool: .highlight, points: [CGPoint(x: 70, y: 10), CGPoint(x: 90, y: 30)], color: .yellow, width: 4)
    let blur = Mark(tool: .blur, points: [CGPoint(x: 100, y: 40), CGPoint(x: 140, y: 90)], color: .black, width: 4)
    guard let out = AnnotateRenderer.render(source, marks: [red, fill, blur]) else { return false }
    let edge = pixel(out, 10, 30)                    // Rechteck-Kante
    if !(edge[0] > 200 && edge[1] < 80) { failures.append("rect edge should be red, got \(edge)") }
    if pixel(out, 30, 30) != [255, 255, 255] { failures.append("rect interior must stay untouched") }
    let hl = pixel(out, 80, 20)
    if !(hl[0] > 200 && hl[2] < 200) { failures.append("highlight should tint yellow, got \(hl)") }
    if pixel(out, 105, 60) == pixel(source, 105, 60) && pixel(out, 107, 60) == pixel(source, 107, 60) { failures.append("blur should change striped pixels") }
    if pixel(out, 180, 80) != [255, 255, 255] { failures.append("untouched area must not change") }
    failures.forEach { print("FAIL annotate:", $0) }
    return failures.isEmpty
}
