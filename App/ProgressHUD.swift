import AppKit
import SwiftUI

final class HUDModel: ObservableObject {
    @Published var title = ""
    @Published var total = 1
    @Published var done = 0
}

struct HUDView: View {
    @ObservedObject var model: HUDModel

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text(model.title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                Spacer()
                if model.total > 1 { Text("\(min(model.done + 1, model.total)) of \(model.total)").font(.system(size: 12)).opacity(0.7) }
            }
            if model.total > 1 {
                ProgressView(value: Double(model.done), total: Double(model.total)).progressViewStyle(.linear)
            } else {
                ProgressView().progressViewStyle(.linear)
            }
        }
        .tint(accent)
        .foregroundColor(.white)
        .padding(.horizontal, 20).padding(.vertical, 14)
        .frame(width: 280, height: 64)
        .liquidGlass(in: Capsule())
    }
}

/// Kleiner Fortschrittsbalken unten am Bildschirm; erscheint erst, wenn eine Arbeit länger als 0,4 s dauert.
final class ProgressHUD {
    static let shared = ProgressHUD()
    private let model = HUDModel()
    private var panel: NSPanel?
    private var pending: DispatchWorkItem?
    private var active = 0

    func begin(_ title: String, total: Int) {
        active += 1
        model.title = title
        model.total = max(1, total)
        model.done = 0
        let work = DispatchWorkItem { [weak self] in self?.show() }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }

    func advance() { model.done += 1 }

    func end() {
        active = max(0, active - 1)
        guard active == 0 else { return }
        pending?.cancel()
        pending = nil
        guard let panel else { return }
        NSAnimationContext.runAnimationGroup({ $0.duration = 0.2; panel.animator().alphaValue = 0 },
                                             completionHandler: { panel.orderOut(nil) })
    }

    private func show() {
        if panel == nil {
            let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 280, height: 64),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            p.isOpaque = false
            p.backgroundColor = .clear
            p.hasShadow = false
            p.level = .statusBar
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            p.ignoresMouseEvents = true
            p.contentView = NSHostingView(rootView: HUDView(model: model))
            panel = p
        }
        guard let panel, let screen = NSScreen.main else { return }
        let frame = screen.visibleFrame
        panel.setFrameOrigin(NSPoint(x: frame.midX - 140, y: frame.minY + 60))
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { $0.duration = 0.2; panel.animator().alphaValue = 1 }
    }
}
