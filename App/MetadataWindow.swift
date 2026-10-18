import AppKit
import SwiftUI

struct MetaField: Identifiable, Hashable {
    let group: String
    let tag: String
    let value: String
    var id: String { "\(group):\(tag)" }
}

/// Dünne Hülle um exiftool: Metadaten lesen und selektiv entfernen.
enum ExifTool {
    /// Gruppen, die nicht entfernbar oder nur abgeleitet sind.
    private static let hiddenGroups: Set<String> = ["System", "File", "ExifTool", "Composite"]

    static var path: String? {
        Backend.tool("exiftool")
    }

    private static func run(_ args: [String]) -> (Int32, Data) {
        guard let path else { return (127, Data()) }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: path)
        task.arguments = args
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()
        do { try task.run() } catch { return (127, Data()) }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        return (task.terminationStatus, data)
    }

    private static func text(_ value: Any) -> String {
        switch value {
        case let s as String: return s
        case let a as [Any]: return a.map(text).joined(separator: ", ")
        case let d as [String: Any]: return "(\(d.count) values)"
        default: return "\(value)"
        }
    }

    static func read(_ url: URL) -> [MetaField]? {
        let (status, data) = run(["-json", "-G1", "-a", url.path])
        guard status == 0, let list = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              let dict = list.first else { return nil }
        return dict.compactMap { key, value -> MetaField? in
            let parts = key.split(separator: ":", maxSplits: 1).map(String.init)
            guard parts.count == 2, !hiddenGroups.contains(parts[0]) else { return nil }
            return MetaField(group: parts[0], tag: parts[1], value: text(value))
        }.sorted { ($0.group, $0.tag) < ($1.group, $1.tag) }
    }

    /// Kopie ohne die gewählten Metadaten neben dem Original; alles Nicht-Gewählte bleibt erhalten.
    static func writeCleanCopy(of url: URL, keeping keep: [MetaField]) -> URL? {
        let dir = url.deletingLastPathComponent(), base = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension.isEmpty ? "" : "." + url.pathExtension
        var out = dir.appendingPathComponent("\(base)_clean\(ext)"), n = 2
        while FileManager.default.fileExists(atPath: out.path) {
            out = dir.appendingPathComponent("\(base)_clean-\(n)\(ext)")
            n += 1
        }
        guard (try? FileManager.default.copyItem(at: url, to: out)) != nil else { return nil }
        var args = ["-m", "-overwrite_original", "-all="]
        if !keep.isEmpty { args += ["-tagsfromfile", "@"] + keep.map { "-\($0.group):\($0.tag)" } }
        _ = run(args + [out.path])
        return FileManager.default.fileExists(atPath: out.path) ? out : nil
    }
}

final class MetadataModel: ObservableObject {
    let url: URL
    let fields: [MetaField]
    @Published var selected: Set<String>
    @Published var status = ""

    init(url: URL, fields: [MetaField]) {
        self.url = url
        self.fields = fields
        selected = Set(fields.map(\.id))
    }

    var groups: [(name: String, items: [MetaField])] {
        Dictionary(grouping: fields, by: \.group).map { ($0.key, $0.value) }.sorted { $0.0 < $1.0 }
    }

    func remove() -> URL? {
        let keep = fields.filter { !selected.contains($0.id) }
        return ExifTool.writeCleanCopy(of: url, keeping: keep)
    }
}

struct MetadataView: View {
    @ObservedObject var model: MetadataModel
    let close: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                VStack(spacing: 2) {
                    Text("Metadata").font(.system(size: 18, weight: .semibold))
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
            HStack {
                Text("\(model.selected.count) of \(model.fields.count) selected")
                    .font(.system(size: 14, weight: .medium)).foregroundColor(.white.opacity(0.85))
                Spacer()
                pill("Select All") { model.selected = Set(model.fields.map(\.id)) }
                pill("None") { model.selected = [] }
            }.padding(.horizontal, 18).padding(.bottom, 8)
            if model.fields.isEmpty {
                Spacer()
                Text("No removable metadata found.").foregroundColor(.white.opacity(0.7))
                Spacer()
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(model.groups, id: \.name) { group in
                            VStack(alignment: .leading, spacing: 0) {
                                Text(group.name).font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(.white.opacity(0.6)).padding(.bottom, 4)
                                ForEach(group.items) { field in row(field) }
                            }
                        }
                    }.padding(.horizontal, 18).padding(.bottom, 10)
                }
            }
            Divider().padding(.horizontal, 12)
            HStack {
                Text(model.status).font(.system(size: 12)).foregroundColor(.white.opacity(0.7)).lineLimit(2)
                Spacer()
                Button(action: remove) {
                    Text("Remove Selected Metadata").font(.system(size: 15, weight: .semibold)).foregroundColor(.white)
                        .padding(.horizontal, 18).padding(.vertical, 9)
                        .background(RoundedRectangle(cornerRadius: 10).fill(accent.opacity(model.selected.isEmpty ? 0.35 : 1)))
                }.buttonStyle(.plain).disabled(model.selected.isEmpty)
            }.padding(14)
        }
        .frame(width: 520, height: 600)
        .foregroundColor(.white)
        .focusEffectDisabled()
        .liquidGlass(in: RoundedRectangle(cornerRadius: 36))
    }

    private func pill(_ title: String, _ action: @escaping () -> Void) -> some View {
        Button(title, action: action).buttonStyle(.plain).font(.system(size: 13))
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.12)))
    }

    private func row(_ field: MetaField) -> some View {
        let on = model.selected.contains(field.id)
        return Button {
            if on { model.selected.remove(field.id) } else { model.selected.insert(field.id) }
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: on ? "checkmark.square.fill" : "square")
                    .foregroundColor(on ? accent : .white.opacity(0.5))
                Text(field.tag).font(.system(size: 13, weight: .medium)).frame(width: 150, alignment: .leading).lineLimit(2)
                Text(field.value).font(.system(size: 13)).foregroundColor(.white.opacity(0.7))
                    .frame(maxWidth: .infinity, alignment: .leading).lineLimit(3)
            }
            .padding(.vertical, 5).contentShape(Rectangle())
        }.buttonStyle(.plain)
    }

    private func remove() {
        guard let out = model.remove() else { model.status = "Entfernen fehlgeschlagen"; return }
        NSWorkspace.shared.activateFileViewerSelecting([out])
        close()
    }
}

enum MetadataWindow {
    static func show(_ urls: [URL]) {
        guard ExifTool.path != nil else {
            let alert = NSAlert()
            alert.messageText = "exiftool nicht gefunden"
            alert.informativeText = "Installieren: brew install exiftool"
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
            return
        }
        for url in urls.prefix(3) {
            let model = MetadataModel(url: url, fields: ExifTool.read(url) ?? [])
            GlassWindow.present(size: NSSize(width: 520, height: 600)) { close in MetadataView(model: model, close: close) }
        }
    }
}
