import AppKit
import SwiftUI

/// Designs for the app icon. All are drawn in code, so the Dock icon and the bundle's icns are the same drawing.
enum IconStyle: String, CaseIterable, Identifiable {
    case switchesAuto, switchesPaper, switchesTerminal
    case cords, graphite, paper, terminal, hub, stack, switches, monogram
    var id: String { rawValue }

    /// Auto shows Paper in light mode and Terminal in dark mode.
    func resolved(dark: Bool) -> IconStyle {
        self == .switchesAuto ? (dark ? .switchesTerminal : .switchesPaper) : self
    }

    var title: String {
        switch self {
        case .switchesAuto: "Switches (Auto)"
        case .switchesPaper: "Switches Paper"
        case .switchesTerminal: "Switches Terminal"
        case .cords: "Patch Cords"
        case .graphite: "Graphite"
        case .paper: "Paper"
        case .terminal: "Terminal"
        case .hub: "Hub"
        case .stack: "Stack"
        case .switches: "Switches"
        case .monogram: "Monogram"
        }
    }
}

/// Color family of the Switches icon: everything on it comes from one family, so nothing clashes.
enum SwitchTint: String, CaseIterable, Identifiable {
    case green, blue, mono
    var id: String { rawValue }
    var title: String { rawValue.capitalized }

    /// the two "on" switches (lighter, deeper) and the three corner dots
    func colors(dark: Bool) -> (on: [Color], dots: [Color]) {
        switch self {
        case .green:
            let a = Color(hex: 0x30A46C), b = Color(hex: 0x1F7A4F), c = Color(hex: 0x8FD3AE)
            return ([a, b], [a, c, b])
        case .blue:
            let a = Color(hex: 0x3E8BFD), b = Color(hex: 0x1F5BD6), c = Color(hex: 0x9CC3FF)
            return ([a, b], [a, c, b])
        case .mono:
            let ink = dark ? Color.white : Color(hex: 0x2B2D33)
            return ([ink, ink.opacity(0.75)], [ink.opacity(0.85), ink.opacity(0.55), ink.opacity(0.3)])
        }
    }

    static var current: SwitchTint { SwitchTint(rawValue: UserDefaults.standard.string(forKey: "switchTint") ?? "") ?? .mono }
}

private extension Color {
    static let indigo1 = Color(hex: 0x5B5BD6)
    static let violet1 = Color(hex: 0x8E4EC6)
}

/// The app's mark in one of the icon styles.
struct AppMark: View {
    var size: CGFloat = 64
    var style: IconStyle = .current
    var tint: SwitchTint = .current
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Mark(size: size, style: style.resolved(dark: scheme == .dark), tint: tint)
    }
}

/// One concrete icon design (Auto already resolved).
private struct Mark: View {
    let size: CGFloat
    let style: IconStyle
    let tint: SwitchTint

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
        shape
            .fill(background)
            .overlay(shape.strokeBorder(rim, lineWidth: max(0.5, size * 0.008)))
            .overlay { Canvas { ctx, sz in draw(&ctx, sz) } }
            .clipShape(shape)
            .frame(width: size, height: size)
            .shadow(color: .black.opacity(0.22), radius: size * 0.05, y: size * 0.025)
    }

    private var background: LinearGradient {
        func g(_ a: UInt32, _ b: UInt32) -> LinearGradient {
            LinearGradient(colors: [Color(hex: a), Color(hex: b)], startPoint: .top, endPoint: .bottom)
        }
        switch style {
        case .switchesAuto, .switchesPaper: return g(0xFFFFFF, 0xE9EAEE)
        case .switchesTerminal: return g(0x2B2D33, 0x111215)
        case .cords: return LinearGradient(colors: [.indigo1, .violet1], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .graphite: return g(0x4A4D55, 0x1C1D21)
        case .paper: return g(0xFFFFFF, 0xE9EAEE)
        case .terminal: return g(0x2B2D33, 0x111215)
        case .hub: return g(0x3D8BFD, 0x1557D1)
        case .stack: return g(0x2BB5A0, 0x0E7C6F)
        case .switches: return g(0xFF9F43, 0xF2612D)
        case .monogram: return g(0x26272B, 0x0B0B0D)
        }
    }

    private var rim: Color { style == .paper || style == .switchesPaper ? .black.opacity(0.08) : .white.opacity(0.14) }

    private func draw(_ ctx: inout GraphicsContext, _ sz: CGSize) {
        let w = sz.width, h = sz.height
        func circle(_ c: CGPoint, _ r: CGFloat) -> Path { Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)) }
        func cord(_ a: CGPoint, _ b: CGPoint) -> Path {
            var p = Path()
            p.move(to: a)
            p.addCurve(to: b, control1: CGPoint(x: (a.x + b.x) / 2, y: a.y), control2: CGPoint(x: (a.x + b.x) / 2, y: b.y))
            return p
        }
        let line = { (lw: CGFloat) in StrokeStyle(lineWidth: w * lw, lineCap: .round, lineJoin: .round) }

        switch style {
        case .switchesAuto, .switchesPaper, .switchesTerminal:
            // Paper (3) and Terminal (4) colors on the switches (7): terminal lights in the corner, the "on"
            // switches lit green and amber, one off
            let dark = style == .switchesTerminal
            let palette = tint.colors(dark: dark)
            for (i, c) in palette.dots.enumerated() {
                ctx.fill(circle(CGPoint(x: w * (0.22 + Double(i) * 0.1), y: h * 0.19), w * 0.032), with: .color(c))
            }
            let rows: [(on: Bool, color: Color)] = [(true, palette.on[0]), (false, .clear), (true, palette.on[1])]
            for (i, r) in rows.enumerated() {
                let y = h * (0.38 + Double(i) * 0.19)
                let track = CGRect(x: w * 0.25, y: y - h * 0.068, width: w * 0.5, height: h * 0.136)
                // the off switch needs its own contrast: a darker track with an outline, and an outlined knob
                let off: Color = dark ? Color(hex: 0x5A5D66) : Color(hex: 0xA9ADB8)
                let trackPath = Path(roundedRect: track, cornerRadius: h * 0.068)
                ctx.fill(trackPath, with: .color(r.on ? r.color : off))
                if !r.on {
                    ctx.stroke(trackPath, with: .color(dark ? .white.opacity(0.35) : .black.opacity(0.25)), lineWidth: w * 0.008)
                }
                let knob = CGPoint(x: r.on ? track.maxX - h * 0.068 : track.minX + h * 0.068, y: y)
                var shadow = ctx
                shadow.addFilter(.shadow(color: .black.opacity(dark ? 0.5 : 0.3), radius: w * 0.012, y: w * 0.006))
                let knobColor: Color = r.on ? (tint == .mono && dark ? Color(hex: 0x1B1C20) : .white) : (dark ? Color(hex: 0xE6E7EB) : .white)
                shadow.fill(circle(knob, h * 0.055), with: .color(knobColor))
            }
        case .cords, .graphite, .paper:
            // jacks left and right, patched by crossing cords
            let ys = [0.3, 0.5, 0.7].map { h * $0 }
            let l = w * 0.26, r = w * 0.74
            let ink: Color = style == .paper ? .indigo1 : .white
            let cordColors: [Color] = style == .paper ? [Color(hex: 0xE5484D), Color(hex: 0x30A46C), .indigo1]
                                                       : [ink.opacity(0.55), ink.opacity(0.75), ink]
            for (i, (a, b)) in [(0, 2), (2, 1), (1, 0)].enumerated() {
                ctx.stroke(cord(CGPoint(x: l, y: ys[a]), CGPoint(x: r, y: ys[b])), with: .color(cordColors[i]), style: line(0.055))
            }
            for y in ys {
                for x in [l, r] {
                    ctx.fill(circle(CGPoint(x: x, y: y), w * 0.068), with: .color(style == .paper ? Color(hex: 0x3A3B44) : .white))
                    ctx.fill(circle(CGPoint(x: x, y: y), w * 0.028), with: .color(style == .paper ? .white : (style == .graphite ? Color(hex: 0x2A2C31) : .indigo1)))
                }
            }

        case .terminal:
            // a prompt and three session lights
            var chev = Path()
            chev.move(to: CGPoint(x: w * 0.24, y: h * 0.36))
            chev.addLine(to: CGPoint(x: w * 0.4, y: h * 0.5))
            chev.addLine(to: CGPoint(x: w * 0.24, y: h * 0.64))
            ctx.stroke(chev, with: .color(.white), style: line(0.07))
            ctx.fill(Path(roundedRect: CGRect(x: w * 0.46, y: h * 0.6, width: w * 0.24, height: h * 0.07), cornerRadius: w * 0.035),
                     with: .color(.white.opacity(0.85)))
            for (i, c) in [Color(hex: 0x30A46C), Color(hex: 0xF5A524), Color(hex: 0xE5484D)].enumerated() {
                ctx.fill(circle(CGPoint(x: w * (0.26 + Double(i) * 0.12), y: h * 0.2), w * 0.04), with: .color(c))
            }

        case .hub:
            // one session in the middle, the others around it
            let center = CGPoint(x: w / 2, y: h / 2)
            let n = 6
            let pts = (0..<n).map { i -> CGPoint in
                let a: CGFloat = CGFloat(i) / CGFloat(n) * 2 * .pi - .pi / 2
                let rx: CGFloat = w * 0.29, ry: CGFloat = h * 0.29
                return CGPoint(x: center.x + cos(a) * rx, y: center.y + sin(a) * ry)
            }
            for p in pts {
                var l = Path(); l.move(to: center); l.addLine(to: p)
                ctx.stroke(l, with: .color(.white.opacity(0.55)), style: line(0.03))
            }
            for p in pts { ctx.fill(circle(p, w * 0.065), with: .color(.white)) }
            ctx.fill(circle(center, w * 0.12), with: .color(.white))
            ctx.fill(circle(center, w * 0.05), with: .color(Color(hex: 0x1557D1)))

        case .stack:
            // three session cards, each with a status light
            for (i, c) in [Color(hex: 0xE5484D), Color(hex: 0xF5A524), Color(hex: 0x30A46C)].enumerated() {
                let y = h * (0.24 + Double(i) * 0.18)
                let inset = w * (0.24 - Double(i) * 0.04)
                let rect = CGRect(x: inset, y: y, width: w - inset * 2, height: h * 0.16)
                ctx.fill(Path(roundedRect: rect, cornerRadius: w * 0.04), with: .color(.white.opacity(0.55 + Double(i) * 0.2)))
                ctx.fill(circle(CGPoint(x: rect.minX + w * 0.07, y: rect.midY), w * 0.03), with: .color(c))
                ctx.fill(Path(roundedRect: CGRect(x: rect.minX + w * 0.13, y: rect.midY - h * 0.015, width: rect.width * 0.45, height: h * 0.03),
                              cornerRadius: w * 0.015), with: .color(Color(hex: 0x0E7C6F).opacity(0.55)))
            }

        case .switches:
            // a row of toggle switches, some on
            for (i, on) in [true, false, true].enumerated() {
                let y = h * (0.3 + Double(i) * 0.2)
                let track = CGRect(x: w * 0.27, y: y - h * 0.065, width: w * 0.46, height: h * 0.13)
                ctx.fill(Path(roundedRect: track, cornerRadius: h * 0.065), with: .color(.white.opacity(on ? 0.95 : 0.35)))
                let knobX = on ? track.maxX - h * 0.065 : track.minX + h * 0.065
                ctx.fill(circle(CGPoint(x: knobX, y: y), h * 0.05), with: .color(on ? Color(hex: 0xF2612D) : .white))
            }

        case .monogram:
            // an S drawn as one cord with a jack at each end
            var s = Path()
            s.move(to: CGPoint(x: w * 0.68, y: h * 0.28))
            s.addCurve(to: CGPoint(x: w * 0.36, y: h * 0.42), control1: CGPoint(x: w * 0.6, y: h * 0.18), control2: CGPoint(x: w * 0.3, y: h * 0.24))
            s.addCurve(to: CGPoint(x: w * 0.64, y: h * 0.6), control1: CGPoint(x: w * 0.44, y: h * 0.56), control2: CGPoint(x: w * 0.7, y: h * 0.48))
            s.addCurve(to: CGPoint(x: w * 0.32, y: h * 0.72), control1: CGPoint(x: w * 0.58, y: h * 0.8), control2: CGPoint(x: w * 0.36, y: h * 0.8))
            let grad = GraphicsContext.Shading.linearGradient(Gradient(colors: [.indigo1, .violet1, Color(hex: 0xD6409F)]),
                                                              startPoint: CGPoint(x: w * 0.3, y: h * 0.2), endPoint: CGPoint(x: w * 0.7, y: h * 0.8))
            ctx.stroke(s, with: grad, style: line(0.085))
            for p in [CGPoint(x: w * 0.68, y: h * 0.28), CGPoint(x: w * 0.32, y: h * 0.72)] {
                ctx.fill(circle(p, w * 0.07), with: .color(.white))
                ctx.fill(circle(p, w * 0.03), with: .color(Color(hex: 0x0B0B0D)))
            }
        }
    }
}

extension IconStyle {
    /// the chosen icon (Settings → Appearance)
    static var current: IconStyle {
        IconStyle(rawValue: UserDefaults.standard.string(forKey: "iconStyle") ?? "") ?? .switchesAuto
    }
}

/// The Switches icon in each color family and both themes, with the Dock size, for choosing.
struct IconSheet: View {
    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(SwitchTint.allCases.enumerated()), id: \.element) { i, t in
                VStack(spacing: 14) {
                    HStack(spacing: 18) {
                        AppMark(size: 140, style: .switchesPaper, tint: t).environment(\.colorScheme, .light)
                        AppMark(size: 140, style: .switchesTerminal, tint: t).environment(\.colorScheme, .dark)
                    }
                    HStack(spacing: 8) {
                        AppMark(size: 48, style: .switchesPaper, tint: t)
                        AppMark(size: 48, style: .switchesTerminal, tint: t)
                    }
                    Text("\(["A", "B", "C"][i]). \(t.title)").font(.system(size: 17, weight: .semibold)).foregroundStyle(.black.opacity(0.8))
                }
                .padding(32)
            }
        }
        .background(LinearGradient(colors: [Color(hex: 0xF2F2F5), Color(hex: 0xC9CBD3)], startPoint: .top, endPoint: .bottom))
    }
}

extension View {
    /// Hides the window title in the toolbar (macOS 15+); the window keeps it for the Window menu.
    @ViewBuilder func hidingToolbarTitle() -> some View {
        if #available(macOS 15.0, *) { toolbar(removing: .title) } else { self }
    }
}
