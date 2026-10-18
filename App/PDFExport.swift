import AppKit
import PDFKit

/// Schwärzen und Unterschreiben als reine Funktion über Seitennummern und Rechtecke (testbar ohne UI).
/// Rechtecke liegen im Seitenraum der cropBox (Ursprung unten links, ohne Seitendrehung).
enum PDFEditExporter {
    struct Signature {
        let page: Int
        let rect: CGRect
        let image: CGImage
    }

    /// Rechteck aus dem ungedrehten Seitenraum in den angezeigten (gedrehten) Raum der Seite.
    static func mapRect(_ rect: CGRect, box: CGRect, rotation: Int) -> CGRect {
        let x = rect.minX - box.minX, y = rect.minY - box.minY, w = rect.width, h = rect.height
        let boxW = box.width, boxH = box.height
        switch ((rotation % 360) + 360) % 360 {
        case 90: return CGRect(x: y, y: boxW - x - w, width: h, height: w)
        case 180: return CGRect(x: boxW - x - w, y: boxH - y - h, width: w, height: h)
        case 270: return CGRect(x: boxH - y - h, y: x, width: h, height: w)
        default: return CGRect(x: x, y: y, width: w, height: h)
        }
    }

    static func export(_ document: PDFDocument, redactions: [(page: Int, rect: CGRect)],
                       signatures: [Signature], to url: URL, dpi: CGFloat = 200) -> Bool {
        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data as CFMutableData) else { return false }
        var first = CGRect(x: 0, y: 0, width: 612, height: 792)
        guard let pdf = CGContext(consumer: consumer, mediaBox: &first, nil) else { return false }
        for index in 0..<document.pageCount {
            guard let page = document.page(at: index) else { continue }
            let box = page.bounds(for: .cropBox), rotation = page.rotation
            let size = rotation % 180 == 0 ? box.size : CGSize(width: box.height, height: box.width)
            let reds = redactions.filter { $0.page == index }.map { mapRect($0.rect, box: box, rotation: rotation) }
            let sigs = signatures.filter { $0.page == index }.map { ($0.image, mapRect($0.rect, box: box, rotation: rotation)) }
            page.displaysAnnotations = false
            defer { page.displaysAnnotations = true }
            var media = CGRect(origin: .zero, size: size)
            let info = [kCGPDFContextMediaBox as String: Data(bytes: &media, count: MemoryLayout<CGRect>.size)] as CFDictionary
            pdf.beginPDFPage(info)
            if reds.isEmpty && rotation == 0 {
                // Seite bleibt Vektor; Unterschriften werden aufgelegt
                pdf.saveGState()
                pdf.translateBy(x: -box.minX, y: -box.minY)
                page.draw(with: .cropBox, to: pdf)
                pdf.restoreGState()
            } else {
                // Gedrehte oder geschwärzte Seiten werden gerastert, damit der Text darunter wirklich verschwindet
                let scale = dpi / 72
                let px = CGSize(width: size.width * scale, height: size.height * scale)
                let thumb = page.thumbnail(of: px, for: .cropBox)
                guard let raster = thumb.cgImage(forProposedRect: nil, context: nil, hints: nil),
                      let bitmap = CGContext(data: nil, width: raster.width, height: raster.height, bitsPerComponent: 8, bytesPerRow: 0,
                                             space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { pdf.endPDFPage(); return false }
                bitmap.draw(raster, in: CGRect(x: 0, y: 0, width: raster.width, height: raster.height))
                let k = CGFloat(raster.width) / size.width
                bitmap.setFillColor(CGColor(gray: 0, alpha: 1))
                reds.forEach { bitmap.fill(CGRect(x: $0.minX * k, y: $0.minY * k, width: $0.width * k, height: $0.height * k)) }
                sigs.forEach { bitmap.draw($0.0, in: CGRect(x: $0.1.minX * k, y: $0.1.minY * k, width: $0.1.width * k, height: $0.1.height * k)) }
                if let flat = bitmap.makeImage() { pdf.draw(flat, in: media) }
                pdf.endPDFPage()
                continue
            }
            sigs.forEach { pdf.draw($0.0, in: $0.1) }
            pdf.endPDFPage()
        }
        pdf.closePDF()
        return (try? (data as Data).write(to: url, options: .atomic)) != nil
    }
}

/// Lauffähiger Check: `FileConvert --selftest-pdfedit`.
func runPDFEditSelfTest() -> Bool {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("pdfedit-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let source = dir.appendingPathComponent("in.pdf")
    let ps = "/Helvetica findfont 24 scalefont setfont 100 700 moveto (SECRET123) show showpage " +
             "/Helvetica findfont 24 scalefont setfont 100 700 moveto (KEEPME) show showpage"
    let gs = Process()
    gs.executableURL = URL(fileURLWithPath: Backend.tool("gs") ?? "/opt/homebrew/bin/gs")
    if let lib = Backend.bundledTools?.gsLib { gs.environment = ["GS_LIB": lib] }
    gs.arguments = ["-q", "-dNOPAUSE", "-dBATCH", "-sDEVICE=pdfwrite", "-sOutputFile=\(source.path)", "-c", ps]
    do { try gs.run(); gs.waitUntilExit() } catch { print("FAIL pdfedit: gs missing"); return false }
    guard let doc = PDFDocument(url: source), doc.pageCount == 2 else { print("FAIL pdfedit: sample"); return false }
    var failures: [String] = []

    let sigCtx = CGContext(data: nil, width: 120, height: 40, bitsPerComponent: 8, bytesPerRow: 0,
                           space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    sigCtx.setStrokeColor(CGColor(gray: 0, alpha: 1)); sigCtx.setLineWidth(4)
    sigCtx.move(to: CGPoint(x: 5, y: 5)); sigCtx.addLine(to: CGPoint(x: 115, y: 35)); sigCtx.strokePath()
    let out = dir.appendingPathComponent("out.pdf")
    let ok = PDFEditExporter.export(doc, redactions: [(0, CGRect(x: 90, y: 690, width: 220, height: 40))],
                                    signatures: [.init(page: 1, rect: CGRect(x: 100, y: 600, width: 120, height: 40), image: sigCtx.makeImage()!)], to: out)
    if !ok { failures.append("export failed") }
    if let result = PDFDocument(url: out) {
        if result.pageCount != 2 { failures.append("page count \(result.pageCount)") }
        if (result.page(at: 0)?.string ?? "").contains("SECRET123") { failures.append("redacted text still extractable") }
        if !(result.page(at: 1)?.string ?? "").contains("KEEPME") { failures.append("unredacted page must keep its text") }
        // Schwärzung ist wirklich schwarz
        if let img = result.page(at: 0)?.thumbnail(of: CGSize(width: 612, height: 792), for: .cropBox).cgImage(forProposedRect: nil, context: nil, hints: nil),
           let bytes = img.dataProvider?.data.flatMap({ CFDataGetBytePtr($0) }) {
            let x = 150, y = 792 - 710                      // innerhalb des geschwärzten Rechtecks
            let o = y * img.bytesPerRow + x * (img.bitsPerPixel / 8)
            if bytes[o] > 40 { failures.append("redaction area is not black (\(bytes[o]))") }
        }
        if (try? out.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) ?? 0 <= (try? source.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) ?? 0 {
            failures.append("output should be larger than input (raster + signature)")
        }
    } else { failures.append("output unreadable") }
    // Seitendrehung: Rechteck-Abbildung
    let box = CGRect(x: 0, y: 0, width: 600, height: 800)
    let r = CGRect(x: 10, y: 20, width: 100, height: 50)
    if PDFEditExporter.mapRect(r, box: box, rotation: 0) != r { failures.append("rotation 0") }
    if PDFEditExporter.mapRect(r, box: box, rotation: 90) != CGRect(x: 20, y: 490, width: 50, height: 100) { failures.append("rotation 90") }
    if PDFEditExporter.mapRect(r, box: box, rotation: 180) != CGRect(x: 490, y: 730, width: 100, height: 50) { failures.append("rotation 180") }
    if PDFEditExporter.mapRect(r, box: box, rotation: 270) != CGRect(x: 730, y: 10, width: 50, height: 100) { failures.append("rotation 270") }
    failures.forEach { print("FAIL pdfedit:", $0) }
    return failures.isEmpty
}
