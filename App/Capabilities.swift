import Foundation

/// Konvertierungsmatrix kommt aus dem Python-Backend (matrix.py), damit UI und Backend nie auseinanderlaufen.
struct FormatGroup: Identifiable, Decodable {
    let title: String
    let symbol: String
    let rows: [String]
    let cols: [String]
    var id: String { title }
}

struct CapsData: Decodable {
    let groups: [FormatGroup]
    let targets: [String: [String]]
    let wheel: [String: [String]]

    static let empty = CapsData(groups: [], targets: [:], wheel: [:])
}

enum Caps {
    private static let aliases = ["jpeg": "jpg", "tif": "tiff", "htm": "html", "gz": "gzip", "tgz": "gzip",
                                  "aif": "aiff", "markdown": "md"]

    static let data: CapsData = {
        let result = Backend.run(["caps"])
        guard result.0, let json = result.1.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(CapsData.self, from: json) else { return .empty }
        return decoded
    }()

    static var groups: [FormatGroup] { data.groups }

    static func normalize(_ ext: String) -> String {
        let lower = ext.lowercased()
        return aliases[lower] ?? lower
    }

    static func group(of format: String) -> FormatGroup? {
        let key = normalize(format)
        return groups.first { $0.rows.contains(key) }
    }

    static func targets(of format: String) -> [String] { data.targets[normalize(format)] ?? [] }

    /// Reihenfolge im Conversion-Wheel.
    static func wheel(of format: String) -> [String] { data.wheel[normalize(format)] ?? [] }
}
