import AppKit
import SwiftUI

/// Empfängt den Drop auf das Wheel und meldet das Segment unter dem Cursor.
final class WheelDropView: NSView {
    let state: WheelState
    var onDrop: (([URL], Int) -> Void)?
    /// Klick-Modus (Tastenkürzel ohne Drag): Maus-Hover und Klick statt Drop.
    var onClick: ((Int?) -> Void)?
    private var tracking: NSTrackingArea?

    init(state: WheelState) {
        self.state = state
        super.init(frame: NSRect(x: 0, y: 0, width: WheelGeometry.size, height: WheelGeometry.size))
        registerForDraggedTypes([.fileURL])
        let host = NSHostingView(rootView: WheelView(state: state))
        host.frame = bounds
        host.autoresizingMask = [.width, .height]
        addSubview(host)
    }

    required init?(coder: NSCoder) { fatalError("nicht benutzt") }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(area)
        tracking = area
    }

    private func segment(at event: NSEvent) -> Int? {
        let p = convert(event.locationInWindow, from: nil)
        let k = WheelGeometry.size / bounds.width
        return WheelGeometry.index(at: CGPoint(x: p.x * k, y: p.y * k), count: state.items.count)
    }

    override func mouseMoved(with event: NSEvent) {
        guard onClick != nil else { return }
        let hovered = segment(at: event)
        if hovered != state.highlight {
            state.highlight = hovered
            if hovered != nil { WheelController.hapticTick() }
        }
    }

    override func mouseExited(with event: NSEvent) { if onClick != nil { state.highlight = nil } }
    override func mouseDown(with event: NSEvent) { onClick?(segment(at: event)) }

    private func segment(_ sender: NSDraggingInfo) -> Int? {
        let p = convert(sender.draggingLocation, from: nil)
        let k = WheelGeometry.size / bounds.width
        return WheelGeometry.index(at: CGPoint(x: p.x * k, y: p.y * k), count: state.items.count)
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { draggingUpdated(sender) }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        let hovered = segment(sender)
        if hovered != state.highlight {
            state.highlight = hovered
            if hovered != nil { WheelController.hapticTick() }  // Tick beim Wechsel auf ein neues Segment
        }
        return hovered == nil ? [] : .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) { state.highlight = nil }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let index = segment(sender) else { return false }
        onDrop?(WheelController.fileURLs(from: sender.draggingPasteboard), index)
        return true
    }
}

final class WheelController {
    private let state = WheelState()
    private let panel: NSPanel
    private let dropView: WheelDropView
    private var monitors: [Any] = []
    private var timer: Timer?
    private var urls: [URL] = []
    private var current: WheelKind?
    private var isShown = false
    private var clickMode = false
    private var outsideClick: Any?

    /// Wie im Original: Das Wheel zoomt von groß auf Normalgröße.
    private static let zoomStart: CGFloat = 2.2

    init() {
        dropView = WheelDropView(state: state)
        panel = NSPanel(contentRect: dropView.frame, styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        panel.contentView = dropView
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        dropView.onDrop = { [weak self] urls, index in self?.drop(urls, index) }
        dropView.onClick = { [weak self] index in self?.clicked(index) }
    }

    /// Haptisches Feedback, wenn in den Settings "Sound and haptic feedback" an ist.
    static func hapticTick() {
        if UserDefaults.standard.object(forKey: "feedback") as? Bool ?? true {
            NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
        }
    }

    static func fileURLs(from pasteboard: NSPasteboard) -> [URL] {
        let objects = pasteboard.readObjects(forClasses: [NSURL.self],
                                             options: [.urlReadingFileURLsOnly: true]) as? [URL]
        return objects ?? []
    }

    func start() {
        // Rechte Maustaste mitnehmen: Ctrl + Klick zählt für macOS als Rechtsklick.
        let drag = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDragged, .rightMouseDragged]) { [weak self] _ in
            self?.dragTick()
        }
        let up = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseUp, .rightMouseUp]) { [weak self] _ in
            self?.mouseUp()
        }
        monitors = [drag, up].compactMap { $0 }
    }

    /// Nur zur Sichtprüfung: Wheel ohne Drag anzeigen.
    func demo(_ kind: WheelKind, file: URL) {
        urls = [file]
        show(kind)
    }

    /// Nur zur Sichtprüfung: Segment als gehovert markieren.
    func demoHover(_ index: Int) { state.highlight = index }

    /// Während eines Datei-Drags regelmäßig prüfen, welche Wheel-Taste gedrückt ist.
    private func dragTick() {
        guard timer == nil, !clickMode else { return }
        urls = WheelController.fileURLs(from: NSPasteboard(name: .drag))
        guard !urls.isEmpty else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 0.02, repeats: true) { [weak self] _ in self?.pollModifiers() }
    }

    private func pollModifiers() {
        let flags = NSEvent.modifierFlags.intersection(DragModifier.mask)
        let match = WheelKind.allCases.first { flags == $0.modifier.flag }
            ?? WheelKind.allCases.first { flags.contains($0.modifier.flag) }
        guard let kind = match else { return }
        if isShown {
            // Andere Taste getippt: Wheel wechselt, ohne neu zu zoomen.
            if kind != current, apply(kind) { haptic() }
        } else {
            show(kind)
        }
    }

    private func apply(_ kind: WheelKind) -> Bool {
        // Das Apps-Wheel öffnet nur Dateien und schreibt nichts, daher keine Ordner-Prüfung
        guard kind == .apps || urls.allSatisfy({ Folders.isAllowed($0) }) else { return false }
        let items = WheelItems.items(kind, for: urls)
        guard !items.isEmpty else { return false }
        state.items = items
        state.highlight = nil
        state.textOnly = kind == .conversion
        state.center = WheelItems.centerLabel(urls)
        current = kind
        return true
    }

    private func haptic() {
        if UserDefaults.standard.object(forKey: "feedback") as? Bool ?? true {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
        }
    }

    private func centered(_ size: CGFloat, at p: NSPoint) -> NSRect {
        NSRect(x: p.x - size / 2, y: p.y - size / 2, width: size, height: size)
    }

    /// Apps-Wheel per Tastenkürzel an der Mausposition (ohne Dateien, mit Klick).
    func showAppsByHotKey() {
        guard !isShown else { hide(); return }
        urls = []
        clickMode = true
        // Kein Modus-Wechsel per Taste, kein Drag-Timer: nur Hover und Klick
        show(.apps)
        outsideClick = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown]) { [weak self] _ in self?.hide() }
    }

    private func clicked(_ index: Int?) {
        guard clickMode else { return }
        guard let index, state.items.indices.contains(index) else { return hide() }
        let item = state.items[index]
        hide()
        item.run([])
    }

    private func show(_ kind: WheelKind) {
        guard apply(kind) else { return }
        let mouse = NSEvent.mouseLocation
        isShown = true
        panel.setFrame(centered(WheelGeometry.size * Self.zoomStart, at: mouse), display: false)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.28
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(centered(WheelGeometry.size, at: mouse), display: true)
            panel.animator().alphaValue = 1
        }
        haptic()
    }

    private func drop(_ files: [URL], _ index: Int) {
        let items = state.items
        hide()
        guard items.indices.contains(index), !files.isEmpty else { return }
        items[index].run(files)
    }

    private func mouseUp() {
        timer?.invalidate()
        timer = nil
        // Kurz warten: der Drop auf das Panel wird vor dem Ausblenden zugestellt.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in self?.hide() }
    }

    private func hide() {
        timer?.invalidate()
        timer = nil
        if let outsideClick { NSEvent.removeMonitor(outsideClick) }
        outsideClick = nil
        clickMode = false
        guard isShown else { return }
        isShown = false
        current = nil
        state.highlight = nil
        NSAnimationContext.runAnimationGroup({ [panel] in
            $0.duration = 0.12
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            guard self?.isShown == false else { return }
            self?.panel.orderOut(nil)
        })
    }
}
