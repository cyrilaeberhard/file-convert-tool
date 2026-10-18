import SwiftUI

enum FormatPrefs {
    static let levels: [(key: String, label: String, value: Int)] = [
        ("small", "Small", 60), ("balanced", "Balanced", 80), ("high", "High", 92), ("maximum", "Maximum", 100),
    ]
    static let sizes: [(key: String, label: String)] = [
        ("keep", "Keep original dimensions"), ("4096", "Max 4096 px"), ("2048", "Max 2048 px"), ("1080", "Max 1080 px"),
    ]

    static func quality(for format: String) -> Int {
        let key = UserDefaults.standard.string(forKey: "fmt.\(format).quality") ?? "balanced"
        return levels.first { $0.key == key }?.value ?? 80
    }

    static func preserveMetadata(for format: String) -> Bool {
        UserDefaults.standard.object(forKey: "fmt.\(format).metadata") as? Bool ?? true
    }

    static func reset(_ format: String, keys: [String]) {
        keys.forEach { UserDefaults.standard.removeObject(forKey: "fmt.\(format).\($0)") }
    }
}

struct FormatDetail: View {
    let format: String
    @AppStorage private var quality: String
    @AppStorage private var metadata: Bool
    @AppStorage private var compression: String
    @AppStorage private var size: String

    init(format: String) {
        self.format = format
        _quality = AppStorage(wrappedValue: "balanced", "fmt.\(format).quality")
        _metadata = AppStorage(wrappedValue: true, "fmt.\(format).metadata")
        _compression = AppStorage(wrappedValue: "balanced", "fmt.\(format).compression")
        _size = AppStorage(wrappedValue: "keep", "fmt.\(format).size")
    }

    private var isMedia: Bool { ["Images", "Video", "Audio"].contains(Caps.group(of: format)?.title ?? "") }
    private var isImage: Bool { Caps.group(of: format)?.title == "Images" }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("\(format.uppercased()) Settings").font(.title3.bold())
            Text("Input and output format. Converts to \(Caps.targets(of: format).map { $0.uppercased() }.joined(separator: ", ")).")
                .font(.caption).foregroundColor(.secondary)
            if isMedia {
                Text("Conversion Settings").font(.headline).padding(.top, 6)
                HStack {
                    Text("Quality")
                    Picker("", selection: $quality) {
                        ForEach(FormatPrefs.levels, id: \.key) { Text($0.label).tag($0.key) }
                    }.labelsHidden().fixedSize()
                }
                Toggle("Preserve metadata", isOn: $metadata)
                HStack {
                    Spacer()
                    Button("Restore Defaults") { FormatPrefs.reset(format, keys: ["quality", "metadata"]) }
                        .buttonStyle(AccentButton()).fixedSize()
                }
                Divider()
                Text(isImage ? "Image Compression" : "Compression").font(.headline)
                HStack {
                    Text("Compression").fixedSize()
                    Picker("", selection: $compression) {
                        Text("Balanced").tag("balanced")
                        Text("Strong").tag("strong")
                    }.pickerStyle(.segmented).labelsHidden().fixedSize()
                }
                if isImage {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Image size").fixedSize()
                        Picker("", selection: $size) {
                            ForEach(FormatPrefs.sizes, id: \.key) { Text($0.label).tag($0.key) }
                        }.labelsHidden().fixedSize()
                    }
                }
                Text("Stärke und Bildgröße werden noch nicht angewendet.")
                    .font(.caption2).foregroundColor(.secondary)
                HStack {
                    Spacer()
                    Button("Restore Compression Defaults") {
                        FormatPrefs.reset(format, keys: ["compression", "size"])
                    }.buttonStyle(AccentButton()).lineLimit(1).fixedSize()
                }
            } else {
                Text("No conversion settings for this format.").foregroundColor(.secondary).padding(.top, 6)
            }
            Spacer()
        }
    }
}

struct AccentButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundColor(accent)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 8).fill(accent.opacity(configuration.isPressed ? 0.25 : 0.12)))
    }
}

struct FormatsTab: View {
    @State private var search = ""
    @State private var selection = "jpg"

    private func visible(_ group: FormatGroup) -> [String] {
        search.isEmpty ? group.rows : group.rows.filter { $0.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(spacing: 8) {
                HStack {
                    Image(systemName: "magnifyingglass").foregroundColor(.secondary)
                    TextField("Search", text: $search).textFieldStyle(.plain)
                }
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.25)))
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Caps.groups) { group in
                            let items = visible(group)
                            if !items.isEmpty {
                                Text(group.title).font(.caption).foregroundColor(.secondary).padding(.top, 8)
                                ForEach(items, id: \.self) { f in
                                    Button { selection = f } label: {
                                        Text(f.uppercased())
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .padding(.horizontal, 10).padding(.vertical, 5)
                                            .background(RoundedRectangle(cornerRadius: 8)
                                                .fill(selection == f ? accent.opacity(0.3) : Color.clear))
                                            .contentShape(Rectangle())
                                    }.buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }
            }.frame(width: 120)
            Divider()
            FormatDetail(format: selection).id(selection)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.primary.opacity(0.07)))
    }
}
