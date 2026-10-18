import AppKit
import QuickLookThumbnailing
import SwiftUI

/// Vorschaubild einer Datei (QuickLook), bis es da ist das Dateisymbol.
struct FileThumbnail: View {
    let url: URL
    let size: CGSize
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fit)
            } else {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().aspectRatio(contentMode: .fit)
            }
        }
        .frame(width: size.width, height: size.height)
        .onAppear(perform: load)
    }

    private func load() {
        let request = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: size.width * 2, height: size.height * 2),
                                                   scale: 2, representationTypes: .thumbnail)
        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { rep, _ in
            guard let cg = rep?.cgImage else { return }
            DispatchQueue.main.async { image = NSImage(cgImage: cg, size: .zero) }
        }
    }
}

/// Draht der Büroklammer (drei Bögen), in einer 28 x 76 Box.
private struct ClipWire: Shape {
    func path(in rect: CGRect) -> Path {
        let sx = rect.width / 28, sy = rect.height / 76
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * sx, y: rect.minY + y * sy) }
        var p = Path()
        p.move(to: pt(8, 52))
        p.addLine(to: pt(8, 16))
        p.addArc(center: pt(14, 16), radius: 6 * sx, startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
        p.addLine(to: pt(20, 62))
        p.addArc(center: pt(10, 62), radius: 10 * sx, startAngle: .degrees(0), endAngle: .degrees(180), clockwise: false)
        p.addLine(to: pt(0, 12))
        p.addArc(center: pt(7, 12), radius: 7 * sx, startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
        p.addLine(to: pt(14, 44))
        return p
    }
}

/// Silberne Büroklammer: Draht mit Verlauf, Glanzlinie und Schatten.
struct PaperClip: View {
    var width: CGFloat = 28

    var body: some View {
        let height = width * 76 / 28
        ZStack {
            ClipWire().stroke(Color.black.opacity(0.25), style: StrokeStyle(lineWidth: 4.2, lineCap: .round, lineJoin: .round))
                .offset(x: 1.5, y: 2).blur(radius: 1.5)
            ClipWire().stroke(LinearGradient(colors: [Color(white: 0.97), Color(white: 0.62), Color(white: 0.9), Color(white: 0.55)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing),
                              style: StrokeStyle(lineWidth: 3.6, lineCap: .round, lineJoin: .round))
            ClipWire().stroke(Color.white.opacity(0.7), style: StrokeStyle(lineWidth: 0.9, lineCap: .round, lineJoin: .round))
                .offset(x: -0.8, y: -0.8)
        }
        .frame(width: width, height: height)
        .rotationEffect(.degrees(14))
    }
}
