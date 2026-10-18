import AppKit
import PDFKit
import SwiftUI

/// Kompression mit Vorschau: Bild (Qualität, Format, Größe), PDF (drei Stufen), Video (Zielgröße).
final class CompressModel: ObservableObject {
    enum Kind { case image, pdf, video }

    static func kind(of url: URL) -> Kind? {
        switch Caps.group(of: url.pathExtension)?.title {
        case "Images": return Caps.normalize(url.pathExtension) == "svg" ? nil : .image
        case "Video": return .video
        default: return Caps.normalize(url.pathExtension) == "pdf" ? .pdf : nil
        }
    }

    let url: URL
    let kind: Kind
    let originalSize: Int
    @Published var format: String
    @Published var quality: Double
    @Published var maxEdge: Int
    @Published var resultURL: URL?
    @Published var resultSize: Int?
    @Published var busy = false
    @Published var error: String?
    @Published var pdfLevel = "medium"
    @Published var pdfByPercent = true
    @Published var reducePercent = 50.0
    @Published var pdfResults: [String: (url: URL, size: Int)] = [:]
    @Published var targetMB: Double
    private var generation = 0
    private let work = FileManager.default.temporaryDirectory.appendingPathComponent("fc-compress-\(UUID().uuidString)")

    init?(url: URL) {
        guard let kind = Self.kind(of: url) else { return nil }
        self.url = url
        self.kind = kind
        originalSize = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        let ext = Caps.normalize(url.pathExtension)
        format = ["jpg", "webp", "heic", "avif"].contains(ext) ? ext : "webp"
        let strong = (UserDefaults.standard.string(forKey: "fmt.\(ext).compression") ?? "balanced") == "strong"
        quality = strong ? 55 : 75
        maxEdge = Int(UserDefaults.standard.string(forKey: "fmt.\(ext).size") ?? "") ?? 0
        targetMB = max(0.05, Double(originalSize) / 1_048_576 * (strong ? 0.35 : 0.6))
        try? FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
    }

    deinit { try? FileManager.default.removeItem(at: work) }

    var savedPercent: Int? {
        guard let size = resultSize, originalSize > 0 else { return nil }
        return Int((1 - Double(size) / Double(originalSize)) * 100)
    }

    func refresh() {
        switch kind {
        case .image: renderImage()
        case .pdf: if pdfResults.isEmpty { renderPDF() }
        case .video: break
        }
    }

    private func renderImage() {
        generation += 1
        let gen = generation, q = Int(quality), fmt = format, edge = maxEdge, src = url
        let out = work.appendingPathComponent("out-\(gen).\(fmt)")
        busy = true
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Backend.run(["recompress", src.path, fmt, "-q", String(q), "--max-edge", String(edge), "-o", out.path])
            let size = (try? out.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            DispatchQueue.main.async {
                guard gen == self.generation else { try? FileManager.default.removeItem(at: out); return }
                self.busy = false
                self.error = result.0 ? nil : result.1
                self.resultURL = result.0 ? out : nil
                self.resultSize = result.0 ? size : nil
            }
        }
    }

    private func renderPDF() {
        busy = true
        let src = url, dir = work
        DispatchQueue.global(qos: .userInitiated).async {
            var found: [String: (URL, Int)] = [:]
            var failure: String?
            for level in ["low", "medium", "high"] {
                let out = dir.appendingPathComponent("\(level).pdf")
                let result = Backend.run(["pdf-compress", src.path, "-l", level, "-o", out.path])
                if result.0 { found[level] = (out, (try? out.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
                else { failure = result.1 }
            }
            DispatchQueue.main.async {
                self.busy = false
                self.pdfResults = found.mapValues { (url: $0.0, size: $0.1) }
                self.error = found.isEmpty ? failure : nil
                self.applyPDFChoice()
            }
        }
    }

    func select(level: String) {
        pdfLevel = level
        resultURL = pdfResults[level]?.url
        resultSize = pdfResults[level]?.size
    }

    /// Größe, die der gewählte Prozentwert höchstens erlaubt.
    var pdfTargetBytes: Int { Int(Double(originalSize) * (1 - reducePercent / 100)) }

    /// true, wenn eine Stufe den Zielwert erreicht.
    var pdfTargetReachable: Bool { pdfResults.values.contains { $0.size <= pdfTargetBytes } }

    /// Prozent-Modus: mildeste Stufe, die das Ziel erreicht, sonst die kleinste.
    func applyPDFChoice() {
        guard pdfByPercent else { return select(level: pdfLevel) }
        let ordered = ["high", "medium", "low"].compactMap { level in pdfResults[level].map { (level, $0.size) } }
        let pick = ordered.first { $0.1 <= pdfTargetBytes } ?? ordered.min { $0.1 < $1.1 }
        if let pick { select(level: pick.0) }
    }

    /// Ergebnis neben das Original legen (ohne etwas zu überschreiben).
    func saveResult() -> URL? {
        guard let source = resultURL else { return nil }
        let dir = url.deletingLastPathComponent(), base = url.deletingPathExtension().lastPathComponent
        let ext = source.pathExtension
        var out = dir.appendingPathComponent("\(base)_compressed.\(ext)"), n = 2
        while FileManager.default.fileExists(atPath: out.path) {
            out = dir.appendingPathComponent("\(base)_compressed-\(n).\(ext)")
            n += 1
        }
        return (try? FileManager.default.copyItem(at: source, to: out)) != nil ? out : nil
    }
}

private func bytes(_ n: Int) -> String { ByteCountFormatter.string(fromByteCount: Int64(n), countStyle: .file) }

/// Vorher/Nachher mit verschiebbarer Trennlinie.
struct BeforeAfter: View {
    let before: NSImage
    let after: NSImage
    @State private var split: CGFloat = 0.5

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Image(nsImage: before).resizable().scaledToFit().frame(width: geo.size.width, height: geo.size.height)
                Image(nsImage: after).resizable().scaledToFit().frame(width: geo.size.width, height: geo.size.height)
                    .mask(alignment: .trailing) { Rectangle().frame(width: geo.size.width * (1 - split)) }
                Rectangle().fill(Color.white).frame(width: 2).shadow(radius: 2)
                    .position(x: geo.size.width * split, y: geo.size.height / 2)
                Circle().fill(Color.white).frame(width: 28, height: 28)
                    .overlay(Image(systemName: "arrow.left.and.right").font(.system(size: 11, weight: .bold)).foregroundColor(.black))
                    .position(x: geo.size.width * split, y: geo.size.height / 2)
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { split = min(1, max(0, $0.location.x / geo.size.width)) })
        }
    }
}

struct CompressView: View {
    @ObservedObject var model: CompressModel
    let close: () -> Void
    @State private var original: NSImage?
    @State private var compressed: NSImage?

    var body: some View {
        if model.kind == .pdf { pdfLayout } else { standardLayout }
    }

    private var standardLayout: some View {
        VStack(spacing: 0) {
            ZStack {
                VStack(spacing: 2) {
                    Text("Compress").font(.system(size: 18, weight: .semibold))
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
            Group {
                switch model.kind {
                case .image: imageBody
                case .pdf: pdfBody
                case .video: videoBody
                }
            }.padding(.horizontal, 18)
            Spacer(minLength: 0)
            Divider().padding(.horizontal, 12)
            footer
        }
        .frame(width: 680, height: 600)
        .foregroundColor(.white)
        .focusEffectDisabled()
        .liquidGlass(in: RoundedRectangle(cornerRadius: 36))
        .onAppear {
            original = NSImage(contentsOf: model.url)
            model.refresh()
        }
        .onChange(of: model.format) { _, _ in model.refresh() }
        .onChange(of: model.maxEdge) { _, _ in model.refresh() }
        .onChange(of: model.quality) { _, _ in debounced() }
        .onChange(of: model.resultURL) { _, new in
            compressed = model.kind == .image ? new.flatMap { NSImage(contentsOf: $0) } : nil
        }
    }

    @State private var pending: DispatchWorkItem?

    // MARK: PDF-Layout (Modus + Prozent-Regler)

    private var pdfLayout: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack {
                Text("Compress").font(.system(size: 20, weight: .semibold))
                HStack {
                    Button(action: close) {
                        Image(systemName: "xmark").font(.system(size: 14, weight: .bold))
                            .frame(width: 38, height: 38).background(Circle().fill(Color.white.opacity(0.16)))
                    }.buttonStyle(.plain)
                    Spacer()
                }
            }.padding(14)
            Divider()
            VStack(alignment: .leading, spacing: 16) {
                Text(model.url.lastPathComponent).font(.system(size: 15)).foregroundColor(Color(red: 0.7, green: 0.93, blue: 0.95)).lineLimit(1)
                Text("Original size: \(bytes(model.originalSize))").font(.system(size: 20, weight: .semibold))
            }.padding(.horizontal, 22).padding(.vertical, 18)
            Divider()
            HStack {
                Text("Mode").font(.system(size: 16)).foregroundColor(.white.opacity(0.65))
                Spacer()
                Picker("", selection: $model.pdfByPercent) {
                    Text("Percentage").tag(true)
                    Text("Preset").tag(false)
                }.labelsHidden().fixedSize()
            }.padding(.horizontal, 22).padding(.vertical, 14)
            Divider()
            Group {
                if model.pdfByPercent { percentControls } else { pdfBody }
            }.padding(.horizontal, 22).padding(.vertical, 16)
            if let error = model.error { Text(error).font(.caption).foregroundColor(.red).lineLimit(2).padding(.horizontal, 22) }
            Spacer(minLength: 0)
            Divider()
            HStack {
                if model.busy { ProgressView().controlSize(.small) }
                Spacer()
                Button(action: save) {
                    Text("Compress").font(.system(size: 16, weight: .semibold)).foregroundColor(.white)
                        .padding(.horizontal, 22).padding(.vertical, 9)
                        .background(RoundedRectangle(cornerRadius: 9).fill(accent))
                }
                .buttonStyle(.plain)
                .disabled(model.resultURL == nil || model.busy)
                .opacity(model.resultURL == nil || model.busy ? 0.4 : 1)
            }.padding(14)
        }
        .frame(width: 560, height: 520)
        .foregroundColor(.white)
        .focusEffectDisabled()
        .liquidGlass(in: RoundedRectangle(cornerRadius: 36))
        .onAppear { model.refresh() }
        .onChange(of: model.pdfByPercent) { _, _ in model.applyPDFChoice() }
        .onChange(of: model.reducePercent) { _, _ in model.applyPDFChoice() }
    }

    private var percentControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 14) {
                Text("Reduce by").font(.system(size: 17, weight: .medium))
                Slider(value: $model.reducePercent, in: 5...95, step: 1).tint(accent)
                Text("\(Int(model.reducePercent))%").font(.system(size: 17, weight: .medium)).frame(width: 48, alignment: .trailing)
            }
            if model.pdfTargetReachable || model.pdfResults.isEmpty {
                Text("Output will be at most \(bytes(model.pdfTargetBytes)).")
                    .font(.system(size: 15)).foregroundColor(.white.opacity(0.6))
            } else if let size = model.resultSize {
                Text("Can't reach \(bytes(model.pdfTargetBytes)). Smallest possible: \(bytes(size)).")
                    .font(.system(size: 15)).foregroundColor(.white.opacity(0.6))
            }
        }
    }

    private func debounced() {
        pending?.cancel()
        let work = DispatchWorkItem { model.refresh() }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
    }

    // MARK: Bild

    private var imageBody: some View {
        VStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 14).fill(Color.black.opacity(0.25))
                if let original, let compressed { BeforeAfter(before: original, after: compressed).clipShape(RoundedRectangle(cornerRadius: 14)) }
                else if let original { Image(nsImage: original).resizable().scaledToFit().padding(6) }
                if model.busy { ProgressView().controlSize(.large) }
            }.frame(height: 330)
            HStack {
                tag("Original", bytes(model.originalSize))
                Spacer()
                if let size = model.resultSize, let saved = model.savedPercent {
                    tag("Compressed", "\(bytes(size))  (\(saved >= 0 ? "−" : "+")\(abs(saved))%)")
                }
            }
            HStack(spacing: 12) {
                Picker("", selection: $model.format) {
                    ForEach(["jpg", "webp", "heic", "avif"], id: \.self) { Text($0.uppercased()).tag($0) }
                }.labelsHidden().fixedSize()
                Text("Quality \(Int(model.quality))").font(.system(size: 13)).frame(width: 78, alignment: .leading)
                Slider(value: $model.quality, in: 1...100).tint(accent)
                Picker("", selection: $model.maxEdge) {
                    Text("Original size").tag(0)
                    Text("Max 4096 px").tag(4096)
                    Text("Max 2048 px").tag(2048)
                    Text("Max 1080 px").tag(1080)
                }.labelsHidden().fixedSize()
            }
            if let error = model.error { Text(error).font(.caption).foregroundColor(.red).lineLimit(2) }
        }
    }

    // MARK: PDF

    private var pdfBody: some View {
        VStack(spacing: 10) {
            VStack(spacing: 10) {
                ForEach([("low", "Strong", "smallest file"), ("medium", "Balanced", "good for screens"), ("high", "Light", "keeps print quality")], id: \.0) { level, title, hint in
                    let size = model.pdfResults[level]?.size
                    Button { model.select(level: level) } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(title).font(.system(size: 15, weight: .semibold))
                                Text(hint).font(.system(size: 12)).opacity(0.65)
                            }
                            Spacer()
                            if let size {
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text(bytes(size)).font(.system(size: 14, weight: .medium))
                                    Text("\(Int((1 - Double(size) / Double(max(1, model.originalSize))) * 100))% saved").font(.system(size: 11)).opacity(0.65)
                                }
                            } else { ProgressView().controlSize(.small) }
                        }
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 12).fill(model.pdfLevel == level ? accent.opacity(0.35) : Color.white.opacity(0.08)))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(model.pdfLevel == level ? accent : .clear, lineWidth: 1.5))
                    }.buttonStyle(.plain)
                }
                tag("Original", bytes(model.originalSize))
                if let error = model.error { Text(error).font(.caption).foregroundColor(.red) }
            }.frame(maxWidth: .infinity)
        }
    }

    // MARK: Video

    private var videoBody: some View {
        VStack(spacing: 16) {
            FileThumbnail(url: model.url, size: CGSize(width: 320, height: 200))
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.black.opacity(0.3)))
            tag("Original", bytes(model.originalSize))
            let maxMB = max(0.2, Double(model.originalSize) / 1_048_576 * 0.95)
            VStack(spacing: 6) {
                Text("Target size \(String(format: "%.1f", model.targetMB)) MB  (about −\(Int((1 - model.targetMB * 1_048_576 / Double(max(1, model.originalSize))) * 100))%)")
                    .font(.system(size: 14, weight: .medium))
                Slider(value: $model.targetMB, in: 0.1...maxMB).tint(accent)
                Text("The video is re-encoded to this size. A preview isn't shown for video.")
                    .font(.system(size: 12)).foregroundColor(.white.opacity(0.6))
            }
        }
    }

    private func tag(_ title: String, _ value: String) -> some View {
        HStack(spacing: 6) {
            Text(title).font(.system(size: 12)).foregroundColor(.white.opacity(0.6))
            Text(value).font(.system(size: 14, weight: .semibold))
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(Capsule().fill(Color.white.opacity(0.1)))
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button(action: save) {
                Text(model.kind == .video ? "Compress Video" : "Save Compressed")
                    .font(.system(size: 15, weight: .semibold)).foregroundColor(.white)
                    .padding(.horizontal, 22).padding(.vertical, 9)
                    .background(RoundedRectangle(cornerRadius: 10).fill(accent))
            }
            .buttonStyle(.plain)
            .disabled(model.kind != .video && (model.resultURL == nil || model.busy))
            .opacity(model.kind != .video && (model.resultURL == nil || model.busy) ? 0.4 : 1)
        }.padding(14)
    }

    private func save() {
        if model.kind == .video {
            Jobs.each([model.url], title: "Compressing video…") { ["compress", $0.path, String(model.targetMB)] }
            close()
            return
        }
        guard let out = model.saveResult() else { return }
        NSWorkspace.shared.activateFileViewerSelecting([out])
        close()
    }
}

enum CompressWindow {
    /// true, wenn das Fenster geöffnet wurde (sonst Format nicht unterstützt).
    @discardableResult
    static func show(_ url: URL) -> Bool {
        guard let model = CompressModel(url: url) else { return false }
        let size = model.kind == .pdf ? NSSize(width: 560, height: 520) : NSSize(width: 680, height: 600)
        GlassWindow.present(size: size) { close in CompressView(model: model, close: close) }
        return true
    }
}
