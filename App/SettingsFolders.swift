import AppKit
import SwiftUI

/// Ordner, in die Ergebnisse neben die Originale geschrieben werden dürfen.
enum Folders {
    private static let key = "allowedFolders"

    static var defaults: [String] {
        let home = NSHomeDirectory()
        return [home, home + "/Downloads"]
    }

    static var allowed: [String] {
        get { UserDefaults.standard.stringArray(forKey: key) ?? defaults }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }

    /// Erlaubt, wenn die Datei in einem Erlaubnis-Ordner oder darunter liegt.
    static func isAllowed(_ file: URL) -> Bool {
        let path = file.resolvingSymlinksInPath().path
        return allowed.contains { path.hasPrefix($0.hasSuffix("/") ? $0 : $0 + "/") }
    }
}

struct FoldersTab: View {
    @State private var folders = Folders.allowed

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Folder Access").font(.callout)
            Card {
                Text("FileConvert saves results beside the originals, but only inside the folders listed here. Allowing a parent folder, such as your home folder, also covers every folder inside it.")
                    .foregroundColor(.secondary)
                ForEach(folders, id: \.self) { path in
                    HStack {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: path)).resizable().frame(width: 32, height: 32)
                        VStack(alignment: .leading) {
                            Text(URL(fileURLWithPath: path).lastPathComponent)
                            Text(path).font(.caption).foregroundColor(.secondary)
                        }
                        Spacer()
                        Button { remove(path) } label: { Image(systemName: "minus.circle").imageScale(.large) }
                            .buttonStyle(.plain).foregroundColor(.secondary)
                    }
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.06)))
                }
                HStack {
                    Spacer()
                    Button("Add Folder…") { add() }.buttonStyle(AccentButton())
                }
            }
            Spacer()
        }
    }

    private func remove(_ path: String) {
        folders = folders.filter { $0 != path }
        Folders.allowed = folders
    }

    private func add() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "Allow"
        panel.message = "Choose a folder FileConvert may save results in."
        guard panel.runModal() == .OK, let url = panel.url, !folders.contains(url.path) else { return }
        folders = folders + [url.path]
        Folders.allowed = folders
    }
}
