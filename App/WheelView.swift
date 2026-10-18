import AppKit
import SwiftUI

struct WheelItem {
    let title: String
    let symbol: String?
    var icon: NSImage? = nil
    let run: ([URL]) -> Void
}

final class WheelState: ObservableObject {
    @Published var items: [WheelItem] = []
    @Published var highlight: Int?
    @Published var center = ""
    @Published var textOnly = false
}

enum WheelGeometry {
    static let size: CGFloat = 304
    static let inner: CGFloat = 46
    static let outer: CGFloat = 132

    /// Mittelwinkel in Grad, 0 = oben, im Uhrzeigersinn.
    static func centerAngle(_ index: Int, _ count: Int) -> Double { Double(index) * 360 / Double(count) }

    /// Segment unter dem Punkt (Wheel-Koordinaten 0...size, y nach oben), nil in der Mitte oder außerhalb.
    static func index(at point: CGPoint, count: Int) -> Int? {
        guard count > 0 else { return nil }
        let c = size / 2
        let dx = point.x - c, dy = (size - point.y) - c
        let radius = hypot(dx, dy)
        guard radius >= inner, radius <= outer + 12 else { return nil }
        var degrees = atan2(dy, dx) * 180 / .pi + 90
        degrees = degrees.truncatingRemainder(dividingBy: 360)
        if degrees < 0 { degrees += 360 }
        let step = 360 / Double(count)
        return Int((degrees + step / 2) / step) % count
    }
}

/// Ringsegment mit echten Rundungen an allen vier Ecken (Eckenradius `corner`, halber Abstand `halfGap`).
struct SliceShape: Shape {
    let index: Int
    let count: Int
    static let corner: CGFloat = 9
    static let halfGap: CGFloat = 1.5

    func path(in rect: CGRect) -> Path {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let ro = Double(WheelGeometry.outer), ri = Double(WheelGeometry.inner)
        if count < 2 {
            var ring = Path()
            ring.addArc(center: c, radius: ro, startAngle: .degrees(0), endAngle: .degrees(360), clockwise: false)
            ring.addArc(center: c, radius: ri, startAngle: .degrees(360), endAngle: .degrees(0), clockwise: true)
            return ring
        }
        let step = 360 / Double(count)
        let mid = WheelGeometry.centerAngle(index, count) - 90
        let t1 = mid - step / 2, t2 = mid + step / 2
        let r = Double(Self.corner), g = Double(Self.halfGap)
        let ao = asin((g + r) / (ro - r)) * 180 / .pi      // Winkelversatz der äußeren Eckmittelpunkte
        let ai = asin((g + r) / (ri + r)) * 180 / .pi      // dasselbe innen
        func polar(_ radius: Double, _ degrees: Double) -> CGPoint {
            CGPoint(x: c.x + radius * cos(degrees * .pi / 180), y: c.y + radius * sin(degrees * .pi / 180))
        }
        var p = Path()
        p.addArc(center: c, radius: ro, startAngle: .degrees(t1 + ao), endAngle: .degrees(t2 - ao), clockwise: false)
        p.addArc(center: polar(ro - r, t2 - ao), radius: r, startAngle: .degrees(t2 - ao), endAngle: .degrees(t2 + 90), clockwise: false)
        p.addArc(center: polar(ri + r, t2 - ai), radius: r, startAngle: .degrees(t2 + 90), endAngle: .degrees(t2 - ai + 180), clockwise: false)
        p.addArc(center: c, radius: ri, startAngle: .degrees(t2 - ai), endAngle: .degrees(t1 + ai), clockwise: true)
        p.addArc(center: polar(ri + r, t1 + ai), radius: r, startAngle: .degrees(t1 + ai + 180), endAngle: .degrees(t1 + 270), clockwise: false)
        p.addArc(center: polar(ro - r, t1 + ao), radius: r, startAngle: .degrees(t1 + 270), endAngle: .degrees(t1 + ao + 360), clockwise: false)
        p.closeSubpath()
        return p
    }
}

struct WheelView: View {
    @ObservedObject var state: WheelState

    private func offset(_ index: Int) -> CGSize {
        let radius = (WheelGeometry.inner + WheelGeometry.outer) / 2 + 2
        let angle = (WheelGeometry.centerAngle(index, state.items.count) - 90) * .pi / 180
        return CGSize(width: cos(angle) * radius, height: sin(angle) * radius)
    }

    /// Liquid Glass (macOS 26) pro Segment; ältere Systeme bekommen eine einfache getönte Fläche.
    @ViewBuilder
    private func slice(_ i: Int) -> some View {
        let shape = SliceShape(index: i, count: state.items.count)
        let hot = state.highlight == i
        ZStack {
            // Fast unsichtbar, aber nicht transparent: Fenster ignorieren Maus und Drag an völlig durchsichtigen Pixeln.
            shape.fill(Color.black.opacity(0.02))
            if #available(macOS 26.0, *) {
                Color.clear
                    .glassEffect(hot ? .regular.tint(accent.opacity(0.55)) : .regular, in: shape)
                    .animation(.easeOut(duration: 0.12), value: state.highlight)
            } else {
                shape.fill(hot ? accent.opacity(0.5) : Color.black.opacity(0.45))
            }
            // Orange Schimmer beim Hovern, unabhängig davon, wie das Glas den Tint darstellt.
            shape.fill(accent.opacity(hot ? 0.34 : 0))
            shape.stroke(accent.opacity(hot ? 0.9 : 0), lineWidth: 1.2)
        }
        .animation(.easeOut(duration: 0.12), value: state.highlight)
    }

    @ViewBuilder
    private var centerPill: some View {
        let text = Text(state.center)
            .font(.system(size: 11, weight: .semibold)).foregroundColor(.white)
            .padding(.horizontal, 12).padding(.vertical, 5)
        if #available(macOS 26.0, *) {
            text.glassEffect(.regular, in: Capsule())
        } else {
            text.background(Capsule().fill(Color.white.opacity(0.16)))
        }
    }

    /// Segment samt Beschriftung; das gehoverte Feld wächst leicht (wie die Sidebar bei Apple).
    private func segment(_ i: Int) -> some View {
        let hot = state.highlight == i
        return ZStack { slice(i); label(i) }
            .frame(width: WheelGeometry.size, height: WheelGeometry.size)
            .scaleEffect(hot ? 1.08 : 1)
            .zIndex(hot ? 1 : 0)
            .animation(.spring(response: 0.26, dampingFraction: 0.68), value: state.highlight)
    }

    private func label(_ i: Int) -> some View {
        VStack(spacing: 3) {
            if let icon = state.items[i].icon {
                Image(nsImage: icon).resizable().frame(width: 34, height: 34)
            } else if let symbol = state.items[i].symbol, !state.textOnly {
                Image(systemName: symbol).font(.system(size: 13, weight: .medium))
            }
            Text(state.textOnly || state.items[i].icon != nil ? state.items[i].title : state.items[i].title.uppercased().replacingOccurrences(of: " ", with: "\n"))
                .font(.system(size: state.textOnly ? 13 : 8, weight: .semibold))
                .multilineTextAlignment(.center)
                .frame(width: 64)
        }
        .foregroundColor(.white)
        .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
        .offset(offset(i))
    }

    private var wheel: some View {
        ZStack {
            ForEach(state.items.indices, id: \.self) { segment($0) }
            Circle().fill(Color.black.opacity(0.02)).frame(width: WheelGeometry.inner * 2)
            centerPill
        }
        .frame(width: WheelGeometry.size, height: WheelGeometry.size)
    }

    var body: some View {
        GeometryReader { geo in
            wheel
                .scaleEffect(geo.size.width / WheelGeometry.size)
                .frame(width: geo.size.width, height: geo.size.height)
        }
    }
}
