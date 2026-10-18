import AppKit
import ServiceManagement
import SwiftUI

let accent = Color(red: 236 / 255, green: 99 / 255, blue: 48 / 255)

enum DragModifier: String, CaseIterable, Identifiable {
    case shift, command, control, option

    /// Nur diese Tasten zählen; Feststell- und Fn-Taste sollen die Erkennung nie stören.
    static let mask: NSEvent.ModifierFlags = [.command, .option, .control, .shift]
    var id: String { rawValue }

    var label: String {
        switch self {
        case .shift: return "⇧  Shift"
        case .command: return "⌘  Command"
        case .control: return "^  Control"
        case .option: return "⌥  Option"
        }
    }

    var symbol: String {
        switch self {
        case .shift: return "⇧"
        case .command: return "⌘"
        case .control: return "^"
        case .option: return "⌥"
        }
    }

    var flag: NSEvent.ModifierFlags {
        switch self {
        case .shift: return .shift
        case .command: return .command
        case .control: return .control
        case .option: return .option
        }
    }
}

enum SettingsTab: String, CaseIterable {
    case general = "General", formats = "Formats", compatibility = "Compatibility"
    case folders = "Folders", watch = "Watch", about = "About"
}

struct Card<Content: View>: View {
    let content: Content
    init(@ViewBuilder _ content: () -> Content) { self.content = content() }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) { content }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color.primary.opacity(0.07)))
    }
}

struct TabBar: View {
    @Binding var selection: SettingsTab

    var body: some View {
        HStack(spacing: 4) {
            ForEach(SettingsTab.allCases, id: \.self) { tab in
                Button(tab.rawValue) { selection = tab }
                    .buttonStyle(.plain).font(.system(size: 13)).lineLimit(1).fixedSize()
                    .padding(.horizontal, 8).padding(.vertical, 6)
                    .background(Capsule().fill(selection == tab ? accent : Color.clear))
                    .foregroundColor(selection == tab ? .white : .primary)
            }
        }
        .padding(4)
        .background(Capsule().fill(Color.primary.opacity(0.07)))
    }
}

struct ModifierRow: View {
    let title: String
    @Binding var selection: String

    var body: some View {
        HStack {
            Text(title)
            Picker("", selection: $selection) {
                ForEach(DragModifier.allCases) { Text($0.label).tag($0.rawValue) }
            }.labelsHidden().fixedSize()
        }
    }
}

struct GeneralTab: View {
    @AppStorage("style") private var style = "glass"
    @AppStorage("launchAtLogin") private var launchAtLogin = false
    @AppStorage("feedback") private var feedback = true
    @AppStorage("conversionWheel") private var conversionWheel = DragModifier.shift.rawValue
    @AppStorage("toolsWheel") private var toolsWheel = DragModifier.command.rawValue
    @AppStorage("actionsWheel") private var actionsWheel = DragModifier.control.rawValue
    @AppStorage("appsWheel") private var appsWheel = DragModifier.option.rawValue
    @AppStorage("floatBehaviour") private var floatBehaviour = "new"
    @AppStorage("terminalApp") private var terminalApp = "Terminal"

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Appearance").font(.callout)
            Card {
                HStack {
                    Text("Style")
                    Picker("", selection: $style) {
                        Text("Glass").tag("glass")
                        Text("Solid").tag("solid")
                    }.pickerStyle(.segmented).labelsHidden().fixedSize()
                }
            }
            Text("General").font(.callout)
            Card {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, on in
                        if on { try? SMAppService.mainApp.register() }
                        else { try? SMAppService.mainApp.unregister() }
                    }
                Divider()
                Toggle("Sound and haptic feedback", isOn: $feedback)
                Divider()
                Text("Drag Modifiers").font(.headline)
                ModifierRow(title: "Conversion wheel", selection: $conversionWheel)
                ModifierRow(title: "Tools wheel", selection: $toolsWheel)
                ModifierRow(title: "Actions wheel", selection: $actionsWheel)
                ModifierRow(title: "Apps wheel", selection: $appsWheel)
                Text("Tap the chosen modifier combination while dragging files.")
                    .font(.caption).foregroundColor(.secondary)
                Divider()
                HStack {
                    Text("Apps wheel shortcut")
                    ShortcutRecorder()
                    Spacer()
                    Button("Edit Apps…") { AppsEditorWindow.show() }.buttonStyle(AccentButton())
                }
                Divider()
                HStack {
                    Text("Float Behaviour")
                    Picker("", selection: $floatBehaviour) {
                        Text("Create a New Float").tag("new")
                        Text("Add Files to an Existing Float").tag("existing")
                    }.labelsHidden().fixedSize()
                }
                Divider()
                HStack {
                    Text("Terminal app")
                    Picker("", selection: $terminalApp) {
                        Text("Terminal").tag("Terminal")
                        Text("iTerm").tag("iTerm")
                    }.labelsHidden().fixedSize()
                }
            }
            Spacer()
        }
    }
}

struct AboutTab: View {
    var body: some View {
        VStack(spacing: 8) {
            Text("🍊").font(.system(size: 56))
            Text("FileConvert").font(.title2.bold())
            Text("Version 1.0 (1)").foregroundColor(.secondary)
            Text("Eigener Nachbau, kein Tangerine-Code.").font(.caption).foregroundColor(.secondary)
            Spacer()
        }.frame(maxWidth: .infinity).padding(.top, 30)
    }
}

/// Fenster, das sich im oberen Streifen verschieben lässt. Der SwiftUI-Inhalt reicht bis unter die
/// Titelleiste und würde sonst alle Klicks dort schlucken.
final class DraggableWindow: NSWindow {
    private let dragStripHeight: CGFloat = 32
    private let trafficLightsWidth: CGFloat = 76

    override func sendEvent(_ event: NSEvent) {
        let point = event.locationInWindow
        if event.type == .leftMouseDown, point.y > frame.height - dragStripHeight, point.x > trafficLightsWidth {
            performDrag(with: event)
            return
        }
        super.sendEvent(event)
    }
}

struct VisualEffect: NSViewRepresentable {
    let material: NSVisualEffectView.Material

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.blendingMode = .behindWindow
        view.state = .active
        view.material = material
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) { view.material = material }
}

struct SettingsView: View {
    @AppStorage("style") private var style = "glass"
    @AppStorage("settingsTab") private var tabName = SettingsTab.general.rawValue

    private var tab: Binding<SettingsTab> {
        Binding(get: { SettingsTab(rawValue: tabName) ?? .general }, set: { tabName = $0.rawValue })
    }

    var body: some View {
        VStack(spacing: 12) {
            TabBar(selection: tab)
            switch tab.wrappedValue {
            case .general: GeneralTab()
            case .formats: FormatsTab()
            case .compatibility: CompatibilityTab()
            case .folders: FoldersTab()
            case .watch: WatchTab()
            case .about: AboutTab()
            }
        }
        .padding(EdgeInsets(top: 32, leading: 16, bottom: 16, trailing: 16))
        .frame(width: 456, height: 650)
        .background((style == "glass" ? AnyView(VisualEffect(material: .hudWindow))
                                      : AnyView(Color(nsColor: .windowBackgroundColor))).ignoresSafeArea())
        .tint(accent)
    }
}

final class SettingsWindow {
    static let shared = SettingsWindow()
    private var window: NSWindow?

    func show() {
        if window == nil {
            let w = DraggableWindow(contentViewController: NSHostingController(rootView: SettingsView()))
            w.title = "FileConvert Settings"
            w.styleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
            w.titlebarAppearsTransparent = true
            w.isOpaque = false
            w.backgroundColor = .clear
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
