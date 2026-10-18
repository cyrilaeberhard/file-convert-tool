import AppKit
import SwiftUI

/// Regeln "Ordner beobachten": neue Dateien eines Typs werden automatisch umgewandelt.
struct WatchTab: View {
    @State private var rules = WatchStore.rules
    @State private var folder = ""
    @State private var from = "heic"
    @State private var to = "jpg"
    @State private var trash = false

    private var sources: [String] { Caps.groups.flatMap(\.rows).filter { !Caps.targets(of: $0).isEmpty } }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Watch Folders").font(.callout)
            Card {
                Text("New files in a watched folder are converted automatically. Existing files are not touched.")
                    .foregroundColor(.secondary).font(.callout)
                ForEach($rules) { $rule in
                    HStack(spacing: 8) {
                        Toggle("", isOn: $rule.enabled).labelsHidden().onChange(of: rule.enabled) { _, _ in save() }
                        VStack(alignment: .leading, spacing: 1) {
                            Text("\(rule.from.uppercased()) → \(rule.to.uppercased())").font(.system(size: 13, weight: .semibold))
                            Text(rule.folder + (rule.trashOriginal ? "  ·  original to Trash" : ""))
                                .font(.caption).foregroundColor(.secondary).lineLimit(1).truncationMode(.middle)
                        }
                        Spacer()
                        Button { rules.removeAll { $0.id == rule.id }; save() } label: { Image(systemName: "minus.circle").imageScale(.large) }
                            .buttonStyle(.plain).foregroundColor(.secondary)
                    }
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.06)))
                }
                Divider()
                Text("New rule").font(.headline)
                HStack {
                    Button(folder.isEmpty ? "Choose Folder…" : URL(fileURLWithPath: folder).lastPathComponent) { choose() }
                        .buttonStyle(AccentButton())
                    Picker("", selection: $from) { ForEach(sources, id: \.self) { Text($0.uppercased()).tag($0) } }
                        .labelsHidden().fixedSize().onChange(of: from) { _, new in to = Caps.targets(of: new).first ?? to }
                    Text("→")
                    Picker("", selection: $to) { ForEach(Caps.targets(of: from), id: \.self) { Text($0.uppercased()).tag($0) } }
                        .labelsHidden().fixedSize()
                }
                Toggle("Move original to Trash after converting", isOn: $trash)
                HStack {
                    Spacer()
                    Button("Add Rule") { add() }.buttonStyle(AccentButton()).disabled(folder.isEmpty).opacity(folder.isEmpty ? 0.4 : 1)
                }
            }
            Spacer()
        }
    }

    private func save() { WatchStore.rules = rules }

    private func choose() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "Watch"
        panel.message = "Choose a folder to watch for new files."
        if panel.runModal() == .OK, let url = panel.url { folder = url.path }
    }

    private func add() {
        guard Folders.isAllowed(URL(fileURLWithPath: folder).appendingPathComponent("x")) else {
            let alert = NSAlert()
            alert.messageText = "Ordner nicht erlaubt"
            alert.informativeText = "Füge ihn zuerst im Tab Folders hinzu."
            alert.runModal()
            return
        }
        rules.append(WatchRule(folder: folder, from: from, to: to, trashOriginal: trash))
        folder = ""
        save()
    }
}
