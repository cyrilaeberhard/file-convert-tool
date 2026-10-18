import AppKit
import SwiftUI

/// Gespeicherte Unterschrift (PNG mit Transparenz) in den Einstellungen der App.
enum SignatureStore {
    private static let key = "signatureImage"

    static var image: NSImage? {
        get { UserDefaults.standard.data(forKey: key).flatMap { NSImage(data: $0) } }
        set {
            guard let newValue, let tiff = newValue.tiffRepresentation, let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
            else { UserDefaults.standard.removeObject(forKey: key); return }
            UserDefaults.standard.set(png, forKey: key)
        }
    }

    /// Weißen Hintergrund eines Scans durchsichtig machen: je heller der Pixel, desto transparenter.
    static func keyOutWhite(_ source: NSImage) -> NSImage? {
        guard let cg = source.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let w = cg.width, h = cg.height
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue), let data = ctx.data else { return nil }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        let bytes = data.bindMemory(to: UInt8.self, capacity: w * h * 4)
        for i in 0..<(w * h) {
            let o = i * 4
            let luminance = (Int(bytes[o]) * 3 + Int(bytes[o + 1]) * 6 + Int(bytes[o + 2])) / 10
            let alpha = UInt8(max(0, min(255, (255 - luminance) * 2)))
            let ink = Int(luminance) * Int(alpha) / 255     // vormultipliert
            bytes[o] = UInt8(ink); bytes[o + 1] = UInt8(ink); bytes[o + 2] = UInt8(ink); bytes[o + 3] = alpha
        }
        guard let out = ctx.makeImage() else { return nil }
        return NSImage(cgImage: out, size: NSSize(width: w, height: h))
    }
}

struct SignaturePad: View {
    let done: (NSImage) -> Void
    let close: () -> Void
    @State private var strokes: [[CGPoint]] = []
    private let size = CGSize(width: 480, height: 170)

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Button(action: close) {
                    Image(systemName: "xmark").font(.system(size: 13, weight: .bold))
                        .frame(width: 34, height: 34).background(Circle().fill(Color.white.opacity(0.16)))
                }.buttonStyle(.plain)
                Spacer()
                Text("Your Signature").font(.system(size: 18, weight: .semibold))
                Spacer()
                Color.clear.frame(width: 34, height: 34)
            }
            ZStack {
                RoundedRectangle(cornerRadius: 14).fill(Color.white)
                Canvas { context, _ in
                    for stroke in strokes where stroke.count > 1 {
                        var path = Path()
                        path.addLines(stroke)
                        context.stroke(path, with: .color(.black), style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                    }
                }
                if strokes.isEmpty { Text("Draw here").foregroundColor(.black.opacity(0.25)) }
            }
            .frame(width: size.width, height: size.height)
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { value in
                    if value.translation == .zero { strokes.append([value.location]) }
                    else if !strokes.isEmpty { strokes[strokes.count - 1].append(value.location) }
                })
            HStack {
                Button("Clear") { strokes = [] }.buttonStyle(AccentButton())
                Button("Choose Image…") { chooseImage() }.buttonStyle(AccentButton())
                Spacer()
                Button(action: use) {
                    Text("Use Signature").font(.system(size: 15, weight: .semibold)).foregroundColor(.white)
                        .padding(.horizontal, 20).padding(.vertical, 9)
                        .background(RoundedRectangle(cornerRadius: 10).fill(accent))
                }.buttonStyle(.plain).disabled(strokes.isEmpty).opacity(strokes.isEmpty ? 0.4 : 1)
            }
        }
        .padding(18)
        .frame(width: 520, height: 330)
        .foregroundColor(.white)
        .focusEffectDisabled()
        .liquidGlass(in: RoundedRectangle(cornerRadius: 32))
    }

    private func use() {
        let scale: CGFloat = 3
        guard let ctx = CGContext(data: nil, width: Int(size.width * scale), height: Int(size.height * scale), bitsPerComponent: 8,
                                  bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
        ctx.scaleBy(x: scale, y: scale)
        ctx.setStrokeColor(CGColor(gray: 0.05, alpha: 1))
        ctx.setLineWidth(3); ctx.setLineCap(.round); ctx.setLineJoin(.round)
        for stroke in strokes where stroke.count > 1 {
            ctx.move(to: CGPoint(x: stroke[0].x, y: size.height - stroke[0].y))
            stroke.dropFirst().forEach { ctx.addLine(to: CGPoint(x: $0.x, y: size.height - $0.y)) }
            ctx.strokePath()
        }
        guard let image = ctx.makeImage() else { return }
        done(trim(NSImage(cgImage: image, size: size)))
    }

    /// Leeren Rand um die Zeichnung abschneiden.
    private func trim(_ image: NSImage) -> NSImage {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil), let data = cg.dataProvider?.data,
              let b = CFDataGetBytePtr(data) else { return image }
        var minX = cg.width, minY = cg.height, maxX = 0, maxY = 0
        for y in 0..<cg.height { for x in 0..<cg.width where b[y * cg.bytesPerRow + x * 4 + 3] > 8 {
            minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
        } }
        guard maxX > minX, maxY > minY, let cropped = cg.cropping(to: CGRect(x: minX - 4, y: minY - 4, width: maxX - minX + 8, height: maxY - minY + 8)) else { return image }
        return NSImage(cgImage: cropped, size: NSSize(width: cropped.width, height: cropped.height))
    }

    private func chooseImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .heic]
        panel.message = "Choose a picture of your signature (dark ink on light paper)."
        guard panel.runModal() == .OK, let url = panel.url, let image = NSImage(contentsOf: url),
              let keyed = SignatureStore.keyOutWhite(image) else { return }
        done(keyed)
    }
}

enum SignatureWindow {
    /// Zeichnen oder Bild wählen; das Ergebnis wird gespeichert und zurückgegeben.
    static func show(completion: @escaping (NSImage) -> Void) {
        GlassWindow.present(size: NSSize(width: 520, height: 330)) { close in
            SignaturePad(done: { image in
                SignatureStore.image = image
                completion(image)
                close()
            }, close: close)
        }
    }
}
