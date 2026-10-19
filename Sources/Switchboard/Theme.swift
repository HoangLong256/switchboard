import AppKit
import SessionCore
import SwiftUI

/// Status and git colors.
enum Palette {
    static let need = Color(hex: 0xE5341F)
    static let block = Color(hex: 0xF08C00)
    static let busy = Color(hex: 0x12A150)
    static let wait = Color(hex: 0x8B5CF6)
    static let shell = Color(hex: 0x2F6FED)
    static let idle = Color(nsColor: .tertiaryLabelColor)
    static let off = Color(nsColor: .quaternaryLabelColor)

    /// git status in the folder sidebar
    static let modified = Color(hex: 0xD97706)
    static let added = Color(hex: 0x12A150)
    static let deleted = Color(hex: 0xE5341F)
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}

/// Classification from SessionCore plus the color for dot and label.
struct Status: Equatable {
    let core: SessionStatus
    var rank: Int { core.rank }
    var label: String { core.label }
    var why: String? { core.why }

    init(_ s: Session, tmuxCommand: String?) { core = SessionStatus(s, tmuxCommand: tmuxCommand) }

    var color: Color {
        switch core.cls {
        case "need": Palette.need
        case "block": Palette.block
        case "busy": Palette.busy
        case "wait": Palette.wait
        case "shell": Palette.shell
        case "off": Palette.off
        default: Palette.idle
        }
    }

    /// pulsing dot while working
    var active: Bool { core.cls == "busy" }
}

/// "<1 min", "12 min", "3 h", "2 d" for "time in status".
func dur(_ iso: String?, now: Date = Date()) -> String {
    guard let iso, let d = parseISO(iso) else { return "" }
    let s = max(0, now.timeIntervalSince(d))
    if s < 60 { return "<1 min" }
    if s < 3600 { return "\(Int((s / 60).rounded())) min" }
    if s < 86400 { return "\(Int((s / 3600).rounded())) h" }
    return "\(Int((s / 86400).rounded())) d"
}

func ago(_ iso: String?, now: Date = Date()) -> String {
    let d = dur(iso, now: now)
    return d.isEmpty ? "" : (d == "<1 min" ? "just now" : "\(d) ago")
}

/// `~/…` instead of the home folder, for paths shown in the UI.
func abbreviated(_ path: String) -> String { (path as NSString).abbreviatingWithTildeInPath }
