import AppKit
import CoreImage
import Vision

/// Freisteller mit Apples Vision (Vordergrund-Maske), Ergebnis als PNG mit Transparenz.
enum BackgroundRemover {
    enum Failure: LocalizedError {
        case unreadable, noSubject, writeFailed

        var errorDescription: String? {
            switch self {
            case .unreadable: return "Bild konnte nicht gelesen werden"
            case .noSubject: return "Kein Motiv im Bild erkannt"
            case .writeFailed: return "Ergebnis konnte nicht gespeichert werden"
            }
        }
    }

    private static func outputURL(for url: URL) -> URL {
        let dir = url.deletingLastPathComponent(), base = url.deletingPathExtension().lastPathComponent
        var out = dir.appendingPathComponent("\(base)_nobg.png"), n = 2
        while FileManager.default.fileExists(atPath: out.path) {
            out = dir.appendingPathComponent("\(base)_nobg-\(n).png")
            n += 1
        }
        return out
    }

    static func removeBackground(from url: URL) throws -> URL {
        guard let input = CIImage(contentsOf: url, options: [.applyOrientationProperty: true]) else { throw Failure.unreadable }
        let handler = VNImageRequestHandler(ciImage: input, options: [:])
        let request = VNGenerateForegroundInstanceMaskRequest()
        try handler.perform([request])
        guard let result = request.results?.first, !result.allInstances.isEmpty else { throw Failure.noSubject }
        let buffer = try result.generateMaskedImage(ofInstances: result.allInstances, from: handler, croppedToInstancesExtent: false)
        let output = CIImage(cvPixelBuffer: buffer)
        let out = outputURL(for: url)
        let context = CIContext()
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              (try? context.writePNGRepresentation(of: output, to: out, format: .RGBA8, colorSpace: space)) != nil
        else { throw Failure.writeFailed }
        return out
    }

    /// Anteil durchsichtiger Pixel (für den Selbsttest).
    static func transparentShare(of url: URL) -> Double? {
        guard let image = NSImage(contentsOf: url), let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let data = cg.dataProvider?.data, let bytes = CFDataGetBytePtr(data), cg.bitsPerPixel == 32 else { return nil }
        let total = cg.width * cg.height
        var clear = 0
        let alphaFirst = cg.alphaInfo == .premultipliedFirst || cg.alphaInfo == .first
        for i in 0..<total where bytes[i * 4 + (alphaFirst ? 0 : 3)] < 10 { clear += 1 }
        return Double(clear) / Double(total)
    }
}
