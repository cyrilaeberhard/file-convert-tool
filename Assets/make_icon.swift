// Zeichnet das App-Icon: Assets/icon_1024.png
import AppKit
let s: CGFloat = 1024
let img = NSImage(size: NSSize(width: s, height: s))
img.lockFocus()
let rect = NSRect(x: 100, y: 100, width: 824, height: 824)
let bg = NSBezierPath(roundedRect: rect, xRadius: 185, yRadius: 185)
NSGradient(starting: NSColor(red: 0.95, green: 0.55, blue: 0.32, alpha: 1),
           ending: NSColor(red: 0.82, green: 0.36, blue: 0.20, alpha: 1))!.draw(in: bg, angle: -90)
let c = NSPoint(x: s / 2, y: s / 2)
NSColor.white.setStroke()
let ring = NSBezierPath(ovalIn: NSRect(x: c.x - 260, y: c.y - 260, width: 520, height: 520))
ring.lineWidth = 56; ring.stroke()
NSColor.white.setFill()
NSBezierPath(ovalIn: NSRect(x: c.x - 78, y: c.y - 78, width: 156, height: 156)).fill()
for a in stride(from: 0.0, to: 360.0, by: 120.0) {
    let r = (a + 90) * .pi / 180
    let l = NSBezierPath()
    l.lineWidth = 40; l.lineCapStyle = .round
    l.move(to: NSPoint(x: c.x + 110 * cos(r), y: c.y + 110 * sin(r)))
    l.line(to: NSPoint(x: c.x + 232 * cos(r), y: c.y + 232 * sin(r)))
    l.stroke()
}
img.unlockFocus()
let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "Assets/icon_1024.png"))
