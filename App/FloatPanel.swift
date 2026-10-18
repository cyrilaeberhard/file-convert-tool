import AppKit
import Combine
import SwiftUI

extension View {
    /// Liquid Glass auf macOS 26, sonst eine Material-Fläche.
    @ViewBuilder
    func liquidGlass<S: Shape>(in shape: S) -> some View {
        if #available(macOS 26.0, *) {
            self.glassEffect(.regular, in: shape)
        } else {
            self.background(.ultraThinMaterial, in: shape)
        }
    }
}

final class FloatModel: ObservableObject {
    @Published var files: [URL]
    @Published var expanded = false
    init(files: [URL]) { self.files = files }
}

/// Vorschau-Karte mit Büroklammer (bei mehreren Dateien mit Stapel-Effekt).
struct FloatCard: View {
    let files: [URL]
    static let size = CGSize(width: 112, height: 136)

    var body: some View {
        ZStack {
            if files.count > 1 {
                RoundedRectangle(cornerRadius: 7).fill(Color.white.opacity(0.85))
                    .frame(width: 68, height: 90).rotationEffect(.degrees(6)).offset(x: 5, y: 2)
            }
            FileThumbnail(url: files[0], size: CGSize(width: 70, height: 92))
                .background(RoundedRectangle(cornerRadius: 7).fill(Color(white: 0.95)))
                .clipShape(RoundedRectangle(cornerRadius: 7))
                .shadow(color: .black.opacity(0.3), radius: 6, y: 3)
            PaperClip(width: 17).offset(x: 24, y: -40)
        }
        .frame(width: Self.size.width, height: Self.size.height)
    }
}

struct FloatView: View {
    @ObservedObject var model: FloatModel
    let close: () -> Void

    var body: some View {
        if model.expanded { expanded } else {
            FloatCard(files: model.files)
                .contentShape(Rectangle())
                .onTapGesture { model.expanded = true }
        }
    }

    private var expanded: some View {
        ZStack(alignment: .topLeading) {
            VStack(spacing: 8) {
                FloatCard(files: model.files).padding(.top, 10)
                Button { model.expanded = false } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.up").font(.system(size: 10, weight: .semibold))
                        Text("\(model.files.count) Item\(model.files.count == 1 ? "" : "s")").font(.system(size: 13))
                    }.foregroundColor(.white.opacity(0.85))
                }.buttonStyle(.plain)
                Divider().padding(.horizontal, 8)
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 16) {
                        ForEach(model.files, id: \.self) { url in
                            VStack(spacing: 6) {
                                FileThumbnail(url: url, size: CGSize(width: 52, height: 68))
                                Text(url.lastPathComponent).font(.system(size: 12)).multilineTextAlignment(.center)
                                    .lineLimit(3).foregroundColor(.white)
                            }
                            .onDrag { NSItemProvider(contentsOf: url) ?? NSItemProvider() }
                        }
                    }.padding(.bottom, 8)
                }
            }
            .padding(.horizontal, 14).padding(.bottom, 12)
            Button(action: close) {
                Image(systemName: "xmark").font(.system(size: 10, weight: .bold)).foregroundColor(.white)
                    .frame(width: 24, height: 24).background(Circle().fill(Color.white.opacity(0.18)))
            }
            .buttonStyle(.plain).padding(10).help("Close Float without deleting files")
        }
        .frame(width: 150)
        .focusEffectDisabled()
        .liquidGlass(in: RoundedRectangle(cornerRadius: 34))
    }
}

/// Panel, das sich an Karte und Kopfbereich verschieben lässt. Ein Klick ohne Bewegung erreicht weiter die Ansicht;
/// die Dateiliste darunter bleibt frei für das Herausziehen von Dateien.
final class FloatPanel: NSPanel {
    var dragZoneHeight: CGFloat = .infinity
    private var downEvent: NSEvent?

    override var canBecomeKey: Bool { true }

    private func inDragZone(_ point: NSPoint) -> Bool {
        let nearClose = point.x < 44 && point.y > frame.height - 44 && dragZoneHeight != .infinity
        return point.y > frame.height - dragZoneHeight && !nearClose
    }

    override func sendEvent(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown:
            downEvent = inDragZone(event.locationInWindow) ? event : nil
        case .leftMouseDragged:
            if let down = downEvent, hypot(event.locationInWindow.x - down.locationInWindow.x,
                                           event.locationInWindow.y - down.locationInWindow.y) > 4 {
                downEvent = nil
                performDrag(with: down)
                return
            }
        case .leftMouseUp:
            downEvent = nil
        default:
            break
        }
        super.sendEvent(event)
    }
}

final class FloatManager {
    static let shared = FloatManager()
    private var floats: [(panel: FloatPanel, model: FloatModel, bag: Set<AnyCancellable>)] = []

    /// "Create a New Float" oder "Add Files to an Existing Float" laut Settings.
    func add(_ urls: [URL]) {
        let mode = UserDefaults.standard.string(forKey: "floatBehaviour") ?? "new"
        if mode == "existing", let last = floats.last {
            last.model.files = last.model.files + urls.filter { !last.model.files.contains($0) }
        } else {
            create(urls)
        }
    }

    /// Nur für Demo-Screenshots.
    func expandLast() { floats.last?.model.expanded = true }

    private func create(_ urls: [URL]) {
        let model = FloatModel(files: urls)
        let panel = FloatPanel(contentRect: NSRect(x: 0, y: 0, width: 112, height: 136),
                               styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        panel.contentView = NSHostingView(rootView: FloatView(model: model) { [weak self, weak panel] in
            guard let panel else { return }
            panel.close()
            self?.floats.removeAll { $0.panel === panel }
        })
        let mouse = NSEvent.mouseLocation
        panel.setFrame(NSRect(x: mouse.x + 20, y: mouse.y - 160, width: 112, height: 136), display: false)
        var bag = Set<AnyCancellable>()
        model.$expanded.combineLatest(model.$files).receive(on: DispatchQueue.main)
            .sink { [weak panel] expanded, files in
                guard let panel else { return }
                let size = expanded ? NSSize(width: 150, height: min(520, 196 + 104 * CGFloat(files.count)))
                                    : FloatCard.size
                panel.dragZoneHeight = expanded ? 170 : .infinity
                var frame = panel.frame
                frame.origin.y += frame.height - size.height   // linke obere Ecke bleibt stehen
                frame.size = size
                panel.setFrame(frame, display: true, animate: true)
            }.store(in: &bag)
        panel.orderFrontRegardless()
        floats.append((panel, model, bag))
    }
}
