import AppKit
import Foundation

struct WatchRule: Codable, Identifiable, Equatable {
    var id = UUID()
    var folder: String
    var from: String          // normalisierte Endung, z. B. "heic"
    var to: String            // Zielformat, z. B. "jpg"
    var trashOriginal = false
    var enabled = true

    /// Passt die Datei zur Regel? (Endung gleich, keine versteckte oder unfertige Datei.)
    func matches(_ url: URL) -> Bool {
        let name = url.lastPathComponent.lowercased()
        let partial = [".crdownload", ".download", ".part", ".tmp", ".partial"].contains { name.hasSuffix($0) }
        return enabled && !name.hasPrefix(".") && !partial && Caps.normalize(url.pathExtension) == from
    }
}

enum WatchStore {
    private static let key = "watchRules"

    static var rules: [WatchRule] {
        get {
            guard let data = UserDefaults.standard.data(forKey: key),
                  let decoded = try? JSONDecoder().decode([WatchRule].self, from: data) else { return [] }
            return decoded
        }
        set {
            UserDefaults.standard.set(try? JSONEncoder().encode(newValue), forKey: key)
            WatchManager.shared.reload()
        }
    }
}

/// Beobachtet Ordner und konvertiert neu hinzugekommene Dateien nach den Regeln.
final class WatchManager {
    static let shared = WatchManager()
    private let queue = DispatchQueue(label: "watch-folders")
    private var sources: [String: DispatchSourceFileSystemObject] = [:]
    private var known: [String: Set<String>] = [:]
    private var produced = Set<String>()
    private var inFlight = Set<String>()
    /// Nur für Tests: Regeln statt der gespeicherten verwenden.
    var overrideRules: [WatchRule]?

    private var rules: [WatchRule] { overrideRules ?? WatchStore.rules }

    private func listing(_ folder: String) -> Set<String> {
        Set((try? FileManager.default.contentsOfDirectory(atPath: folder)) ?? [])
    }

    func reload() {
        queue.async { [self] in
            let wanted = Set(rules.filter(\.enabled).map(\.folder))
            for (folder, source) in sources where !wanted.contains(folder) {
                source.cancel()
                sources[folder] = nil
                known[folder] = nil
            }
            for folder in wanted where sources[folder] == nil { watch(folder) }
        }
    }

    private func watch(_ folder: String) {
        let fd = open(folder, O_EVTONLY)
        guard fd >= 0 else { return }
        known[folder] = listing(folder)    // vorhandene Dateien werden nicht angefasst
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .extend, .rename], queue: queue)
        source.setEventHandler { [weak self] in self?.scan(folder) }
        source.setCancelHandler { close(fd) }
        source.resume()
        sources[folder] = source
    }

    private func scan(_ folder: String) {
        let now = listing(folder)
        let added = now.subtracting(known[folder] ?? [])
        known[folder] = now
        for name in added {
            let url = URL(fileURLWithPath: folder).appendingPathComponent(name)
            guard !produced.contains(url.path), let rule = rules.first(where: { $0.folder == folder && $0.matches(url) }) else { continue }
            process(url, rule)
        }
    }

    /// Wartet, bis die Datei fertig geschrieben ist (Größe bleibt gleich), und konvertiert dann.
    private func process(_ url: URL, _ rule: WatchRule) {
        guard Folders.isAllowed(url), !inFlight.contains(url.path) else { return }
        inFlight.insert(url.path)
        queue.async { [self] in
            var last: Int = -1, stable = 0
            for _ in 0..<120 where stable < 2 {
                let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? -1
                stable = size == last && size > 0 ? stable + 1 : 0
                last = size
                Thread.sleep(forTimeInterval: 0.5)
            }
            defer { inFlight.remove(url.path) }
            guard stable >= 2 else { return }
            convert(url, rule)
        }
    }

    private func convert(_ url: URL, _ rule: WatchRule) {
        DispatchQueue.main.async { ProgressHUD.shared.begin("Converting \(url.lastPathComponent)…", total: 1) }
        let keep = FormatPrefs.preserveMetadata(for: rule.to)
        let args = ["convert", url.path, rule.to, "-q", String(FormatPrefs.quality(for: rule.to))] + (keep ? [] : ["--no-metadata"])
        let result = Backend.run(args)
        if result.0, let out = result.1.split(separator: "\n").last {
            produced.insert(String(out))
            known[url.deletingLastPathComponent().path, default: []].insert(URL(fileURLWithPath: String(out)).lastPathComponent)
            if rule.trashOriginal { NSWorkspace.shared.recycle([url]) }
        }
        DispatchQueue.main.async {
            ProgressHUD.shared.end()
            if UserDefaults.standard.object(forKey: "feedback") as? Bool ?? true { NSSound(named: result.0 ? "Glass" : "Basso")?.play() }
        }
    }
}

/// Lauffähiger Check: `FileConvert --selftest-watch`.
func runWatchSelfTest() -> Bool {
    let dir = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("watch-selftest-\(UUID().uuidString.prefix(6))")
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let rule = WatchRule(folder: dir.path, from: "png", to: "jpg")
    var failures: [String] = []
    if !rule.matches(dir.appendingPathComponent("a.PNG")) { failures.append("matches png") }
    if rule.matches(dir.appendingPathComponent(".hidden.png")) { failures.append("ignores hidden") }
    if rule.matches(dir.appendingPathComponent("a.jpg")) { failures.append("ignores other ext") }
    if rule.matches(dir.appendingPathComponent("a.png.crdownload")) { failures.append("ignores partial") }

    // Vorhandene Datei darf nicht umgewandelt werden, neue schon.
    let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==")!
    try? png.write(to: dir.appendingPathComponent("old.png"))
    let manager = WatchManager.shared
    manager.overrideRules = [rule]
    manager.reload()
    Thread.sleep(forTimeInterval: 1)
    try? png.write(to: dir.appendingPathComponent("new.png"))
    var found = false
    for _ in 0..<40 {
        if FileManager.default.fileExists(atPath: dir.appendingPathComponent("new.jpg").path) { found = true; break }
        Thread.sleep(forTimeInterval: 0.5)
    }
    if !found { failures.append("new.png was not converted") }
    if FileManager.default.fileExists(atPath: dir.appendingPathComponent("old.jpg").path) { failures.append("old.png must stay untouched") }
    manager.overrideRules = []
    manager.reload()
    failures.forEach { print("FAIL watch:", $0) }
    return failures.isEmpty
}
