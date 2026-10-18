import Foundation

enum Casing: String, CaseIterable, Identifiable {
    case keep = "Keep", lower = "lowercase", upper = "UPPERCASE"
    var id: String { rawValue }
}

struct RenameOptions {
    var pattern = "{name}"
    var start = 1
    var padding = 2
    var casing = Casing.keep
    var search = ""
    var replace = ""
}

struct RenameItem {
    let url: URL
    let newName: String
    var changed: Bool { url.lastPathComponent != newName }
}

/// Muster-Umbenennung: {name} {ext} {n} {n:3} {date} {time} {created} {parent}.
enum Renamer {
    private static func format(_ date: Date, _ pattern: String) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = pattern
        return f.string(from: date)
    }

    /// Dateiname ohne verbotene Zeichen; nie leer.
    static func sanitize(_ name: String) -> String {
        let cleaned = name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "untitled" : cleaned
    }

    static func newName(for url: URL, index: Int, options: RenameOptions) -> String {
        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .creationDateKey])
        let modified = values?.contentModificationDate ?? Date()
        let created = values?.creationDate ?? modified
        var base = url.deletingPathExtension().lastPathComponent
        if !options.search.isEmpty { base = base.replacingOccurrences(of: options.search, with: options.replace) }
        var result = options.pattern
        // {n:3} zuerst, damit die Kurzform {n} nicht dazwischenfunkt
        let counter = options.start + index
        let regex = try? NSRegularExpression(pattern: "\\{n:(\\d{1,2})\\}")
        let matches = regex?.matches(in: result, range: NSRange(result.startIndex..., in: result)) ?? []
        for match in matches.reversed() {
            guard let whole = Range(match.range, in: result), let digits = Range(match.range(at: 1), in: result) else { continue }
            let width = Int(result[digits]) ?? options.padding
            result.replaceSubrange(whole, with: String(format: "%0\(width)d", counter))
        }
        let tokens: [(String, String)] = [
            ("{name}", base), ("{ext}", url.pathExtension),
            ("{n}", String(format: "%0\(options.padding)d", counter)),
            ("{date}", format(modified, "yyyy-MM-dd")), ("{time}", format(modified, "HHmmss")),
            ("{created}", format(created, "yyyy-MM-dd")), ("{parent}", url.deletingLastPathComponent().lastPathComponent),
        ]
        for (token, value) in tokens { result = result.replacingOccurrences(of: token, with: value) }
        switch options.casing {
        case .keep: break
        case .lower: result = result.lowercased()
        case .upper: result = result.uppercased()
        }
        result = sanitize(result)
        let ext = url.pathExtension
        return ext.isEmpty || options.pattern.contains("{ext}") ? result : result + "." + ext
    }

    static func plan(_ urls: [URL], _ options: RenameOptions) -> [RenameItem] {
        urls.enumerated().map { RenameItem(url: $1, newName: newName(for: $1, index: $0, options: options)) }
    }

    /// Indizes mit Namenskonflikt: doppelt im Stapel oder bereits vorhanden (und nicht Teil des Stapels).
    static func conflicts(_ items: [RenameItem]) -> Set<Int> {
        var bad = Set<Int>()
        let batch = Set(items.map { $0.url.standardizedFileURL.path.lowercased() })
        var seen: [String: Int] = [:]
        for (index, item) in items.enumerated() {
            let target = item.url.deletingLastPathComponent().appendingPathComponent(item.newName)
            let key = target.path.lowercased()
            if let first = seen[key] { bad.insert(index); bad.insert(first) }
            seen[key] = index
            if item.changed, FileManager.default.fileExists(atPath: target.path), !batch.contains(key) { bad.insert(index) }
        }
        return bad
    }

    /// In zwei Schritten (über Zwischennamen), damit Tausch und Überschneidungen funktionieren.
    static func apply(_ items: [RenameItem]) throws -> [URL] {
        let fm = FileManager.default
        let changing = items.filter(\.changed)
        var temps: [(URL, RenameItem)] = []
        for item in changing {
            let temp = item.url.deletingLastPathComponent().appendingPathComponent(".rename-\(UUID().uuidString)")
            try fm.moveItem(at: item.url, to: temp)
            temps.append((temp, item))
        }
        var results: [URL] = []
        for (temp, item) in temps {
            let target = item.url.deletingLastPathComponent().appendingPathComponent(item.newName)
            try fm.moveItem(at: temp, to: target)
            results.append(target)
        }
        return results
    }
}

/// Lauffähiger Check: `FileConvert --selftest-rename`.
func runRenameSelfTest() -> Bool {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("rename-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let urls = ["b.txt", "a.txt", "Foto Eins.JPG"].map { dir.appendingPathComponent($0) }
    urls.forEach { FileManager.default.createFile(atPath: $0.path, contents: Data("x".utf8)) }
    var failures: [String] = []
    func check(_ ok: Bool, _ what: String) { if !ok { failures.append(what) } }

    var o = RenameOptions()
    o.pattern = "Urlaub_{n}"
    check(Renamer.plan(urls, o).map(\.newName) == ["Urlaub_01.txt", "Urlaub_02.txt", "Urlaub_03.JPG"], "counter")
    o.pattern = "{n:3}-{name}"; o.start = 7; o.casing = .lower
    check(Renamer.plan(urls, o)[2].newName == "009-foto eins.JPG", "padding/lower")
    o = RenameOptions(); o.pattern = "{name}"; o.search = " "; o.replace = "_"
    check(Renamer.plan(urls, o)[2].newName == "Foto_Eins.JPG", "search/replace")
    o = RenameOptions(); o.pattern = "x/{name}:y"
    check(!Renamer.plan(urls, o)[0].newName.contains("/") && !Renamer.plan(urls, o)[0].newName.contains(":"), "sanitize")
    o.pattern = "same"
    check(Renamer.conflicts(Renamer.plan(urls, o)) == [0, 1], "duplicate names flagged")
    o.pattern = "{name}"
    check(Renamer.conflicts(Renamer.plan(urls, o)).isEmpty, "unchanged names are no conflict")
    // Tausch a <-> b funktioniert über Zwischennamen
    let swap = [RenameItem(url: urls[0], newName: "a.txt"), RenameItem(url: urls[1], newName: "b.txt")]
    check((try? Renamer.apply(swap)) != nil, "swap applies")
    check((try? String(contentsOf: urls[0])) == "x", "swap keeps files")
    o = RenameOptions(); o.pattern = "neu_{n}"
    if let result = try? Renamer.apply(Renamer.plan([urls[0], urls[1]], o)) {
        check(result.map(\.lastPathComponent) == ["neu_01.txt", "neu_02.txt"], "apply names")
        check(result.allSatisfy { FileManager.default.fileExists(atPath: $0.path) }, "files exist after apply")
    } else { failures.append("apply failed") }
    failures.forEach { print("FAIL rename:", $0) }
    return failures.isEmpty
}
