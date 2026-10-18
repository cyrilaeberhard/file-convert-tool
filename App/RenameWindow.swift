import AppKit
import SwiftUI

final class RenameModel: ObservableObject {
    let urls: [URL]
    @Published var options = RenameOptions()

    init(urls: [URL]) { self.urls = urls }

    var items: [RenameItem] { Renamer.plan(urls, options) }
}

struct RenameView: View {
    @ObservedObject var model: RenameModel
    let close: () -> Void
    private let tokens = ["{name}", "{n}", "{n:3}", "{date}", "{time}", "{created}", "{parent}"]

    var body: some View {
        let items = model.items
        let conflicts = Renamer.conflicts(items)
        VStack(spacing: 0) {
            header
            VStack(alignment: .leading, spacing: 10) {
                field("Pattern", text: $model.options.pattern)
                HStack(spacing: 6) {
                    ForEach(tokens, id: \.self) { token in
                        Button(token) { model.options.pattern += token }.buttonStyle(.plain)
                            .font(.system(size: 11, design: .monospaced))
                            .padding(.horizontal, 7).padding(.vertical, 4)
                            .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.12)))
                    }
                }
                HStack(spacing: 12) {
                    Stepper("Start \(model.options.start)", value: $model.options.start, in: 0...99999)
                    Stepper("Digits \(model.options.padding)", value: $model.options.padding, in: 1...6)
                    Picker("", selection: $model.options.casing) {
                        ForEach(Casing.allCases) { Text($0.rawValue).tag($0) }
                    }.labelsHidden().fixedSize()
                }.font(.system(size: 13))
                HStack(spacing: 8) {
                    field("Find", text: $model.options.search)
                    field("Replace with", text: $model.options.replace)
                }
            }.padding(.horizontal, 18)
            Divider().padding(14)
            ScrollView {
                VStack(spacing: 4) {
                    ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                        HStack(spacing: 8) {
                            Text(item.url.lastPathComponent).lineLimit(1).foregroundColor(.white.opacity(0.6))
                            Image(systemName: "arrow.right").font(.system(size: 10)).foregroundColor(.white.opacity(0.5))
                            Text(item.newName).lineLimit(1).fontWeight(.medium)
                                .foregroundColor(conflicts.contains(index) ? .red : .white)
                            Spacer(minLength: 0)
                        }.font(.system(size: 13))
                    }
                }.padding(.horizontal, 18)
            }
            Divider().padding(.horizontal, 12)
            HStack {
                Text(conflicts.isEmpty ? "\(items.filter(\.changed).count) of \(items.count) files will change"
                                       : "Name conflicts (red) must be resolved").font(.system(size: 12))
                    .foregroundColor(conflicts.isEmpty ? .white.opacity(0.7) : .red)
                Spacer()
                Button(action: { apply(items) }) {
                    Text("Rename").font(.system(size: 15, weight: .semibold)).foregroundColor(.white)
                        .padding(.horizontal, 22).padding(.vertical, 9)
                        .background(RoundedRectangle(cornerRadius: 10).fill(accent))
                }.buttonStyle(.plain)
                    .disabled(!conflicts.isEmpty || items.allSatisfy { !$0.changed })
                    .opacity(!conflicts.isEmpty || items.allSatisfy { !$0.changed } ? 0.4 : 1)
            }.padding(14)
        }
        .frame(width: 560, height: 600)
        .foregroundColor(.white)
        .focusEffectDisabled()
        .liquidGlass(in: RoundedRectangle(cornerRadius: 36))
    }

    private var header: some View {
        ZStack {
            VStack(spacing: 2) {
                Text("Rename").font(.system(size: 18, weight: .semibold))
                Text("\(model.urls.count) file\(model.urls.count == 1 ? "" : "s")")
                    .font(.system(size: 12)).foregroundColor(.white.opacity(0.65))
            }
            HStack {
                Button(action: close) {
                    Image(systemName: "xmark").font(.system(size: 13, weight: .bold))
                        .frame(width: 34, height: 34).background(Circle().fill(Color.white.opacity(0.16)))
                }.buttonStyle(.plain)
                Spacer()
            }
        }.padding(14)
    }

    private func field(_ title: String, text: Binding<String>) -> some View {
        TextField(title, text: text).textFieldStyle(.plain).font(.system(size: 14))
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.25)))
    }

    private func apply(_ items: [RenameItem]) {
        do {
            let result = try Renamer.apply(items)
            if UserDefaults.standard.object(forKey: "feedback") as? Bool ?? true { NSSound(named: "Glass")?.play() }
            NSWorkspace.shared.activateFileViewerSelecting(result)
            close()
        } catch {
            let alert = NSAlert()
            alert.messageText = "Umbenennen fehlgeschlagen"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }
}

enum RenameWindow {
    static func show(_ urls: [URL]) {
        GlassWindow.present(size: NSSize(width: 560, height: 600)) { close in
            RenameView(model: RenameModel(urls: urls), close: close)
        }
    }
}
