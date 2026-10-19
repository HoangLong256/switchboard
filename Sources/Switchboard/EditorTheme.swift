import AppKit
import EditorKit
import SwiftUI

/// Color themes for the editor, with the palettes of the VS Code themes of the same name.
enum EditorTheme: String, CaseIterable, Identifiable {
    /// Light Modern or Dark Modern, following the app's appearance (VS Code's default themes)
    case automatic
    case lightModern, darkModern, dracula, oneDark, monokai, githubDark, githubLight, nord, solarizedDark, solarizedLight

    var id: String { rawValue }

    var title: String {
        switch self {
        case .automatic: "Automatic"
        case .lightModern: "Light Modern"
        case .darkModern: "Dark Modern"
        case .dracula: "Dracula"
        case .oneDark: "One Dark Pro"
        case .monokai: "Monokai"
        case .githubDark: "GitHub Dark"
        case .githubLight: "GitHub Light"
        case .nord: "Nord"
        case .solarizedDark: "Solarized Dark"
        case .solarizedLight: "Solarized Light"
        }
    }

    /// The concrete palette; Automatic picks one for the current appearance.
    func palette(dark: Bool) -> EditorPalette {
        if self == .automatic { return (dark ? EditorTheme.darkModern : .lightModern).palette(dark: dark) }
        var p = colors
        (p.sidebar, p.accent) = chrome
        p.ansi = ansi
        return p
    }

    /// VS Code's `sideBar.background` and `focusBorder` / button color
    private var chrome: (UInt32, UInt32) {
        switch self {
        case .automatic, .lightModern: (0xF8F8F8, 0x005FB8)
        case .darkModern: (0x181818, 0x0078D4)
        case .dracula: (0x21222C, 0xBD93F9)
        case .oneDark: (0x21252B, 0x528BFF)
        case .monokai: (0x1E1F1C, 0xA6E22E)
        case .githubDark: (0x010409, 0x1F6FEB)
        case .githubLight: (0xF6F8FA, 0x0969DA)
        case .nord: (0x2E3440, 0x88C0D0)
        case .solarizedDark: (0x00212B, 0x2AA198)
        case .solarizedLight: (0xEEE8D5, 0x268BD2)
        }
    }

    /// VS Code's `terminal.ansi*`: black, red, green, yellow, blue, magenta, cyan, white, then the bright ones
    private var ansi: [UInt32] {
        switch self {
        case .automatic, .lightModern:
            [0x000000, 0xCD3131, 0x00BC00, 0x949800, 0x0451A5, 0xBC05BC, 0x0598BC, 0x555555,
             0x666666, 0xCD3131, 0x14CE14, 0xB5BA00, 0x0451A5, 0xBC05BC, 0x0598BC, 0xA5A5A5]
        case .darkModern:
            [0x000000, 0xCD3131, 0x0DBC79, 0xE5E510, 0x2472C8, 0xBC3FBC, 0x11A8CD, 0xE5E5E5,
             0x666666, 0xF14C4C, 0x23D18B, 0xF5F543, 0x3B8EEA, 0xD670D6, 0x29B8DB, 0xE5E5E5]
        case .dracula:
            [0x21222C, 0xFF5555, 0x50FA7B, 0xF1FA8C, 0xBD93F9, 0xFF79C6, 0x8BE9FD, 0xF8F8F2,
             0x6272A4, 0xFF6E6E, 0x69FF94, 0xFFFFA5, 0xD6ACFF, 0xFF92DF, 0xA4FFFF, 0xFFFFFF]
        case .oneDark:
            [0x3F4451, 0xE05561, 0x8CC265, 0xD18F52, 0x4AA5F0, 0xC162DE, 0x42B3C2, 0xD7DAE0,
             0x4F5666, 0xFF616E, 0xA5E075, 0xF0A45D, 0x4DC4FF, 0xDE73FF, 0x4CD1E0, 0xE6E6E6]
        case .monokai:
            [0x333333, 0xC4265E, 0x86B42B, 0xB3B42B, 0x6A7EC8, 0x8C6BC8, 0x56ADBC, 0xE3E3DD,
             0x666666, 0xF92672, 0xA6E22E, 0xE2E22E, 0x819AFF, 0xAE81FF, 0x66D9EF, 0xF8F8F2]
        case .githubDark:
            [0x484F58, 0xFF7B72, 0x3FB950, 0xD29922, 0x58A6FF, 0xBC8CFF, 0x39C5CF, 0xB1BAC4,
             0x6E7681, 0xFFA198, 0x56D364, 0xE3B341, 0x79C0FF, 0xD2A8FF, 0x56D4DD, 0xFFFFFF]
        case .githubLight:
            [0x24292F, 0xCF222E, 0x116329, 0x4D2D00, 0x0969DA, 0x8250DF, 0x1B7C83, 0x6E7781,
             0x57606A, 0xA40E26, 0x1A7F37, 0x633C01, 0x218BFF, 0xA475F9, 0x3192AA, 0x8C959F]
        case .nord:
            [0x3B4252, 0xBF616A, 0xA3BE8C, 0xEBCB8B, 0x81A1C1, 0xB48EAD, 0x88C0D0, 0xE5E9F0,
             0x4C566A, 0xBF616A, 0xA3BE8C, 0xEBCB8B, 0x81A1C1, 0xB48EAD, 0x8FBCBB, 0xECEFF4]
        case .solarizedDark, .solarizedLight:
            [0x073642, 0xDC322F, 0x859900, 0xB58900, 0x268BD2, 0xD33682, 0x2AA198, 0xEEE8D5,
             0x586E75, 0xCB4B16, 0x586E75, 0x657B83, 0x839496, 0x6C71C4, 0x93A1A1, 0xFDF6E3]
        }
    }

    /// Editor colors: background, text, gutter, selection, cursor and syntax
    private var colors: EditorPalette {
        switch self {
        case .automatic: EditorTheme.lightModern.colors
        case .lightModern:
            EditorPalette(dark: false, background: 0xFFFFFF, foreground: 0x3B3B3B, gutter: 0x6E7681, selection: 0xADD6FF,
                          cursor: 0x000000, comment: 0x008000, string: 0xA31515, number: 0x098658, keyword: 0x0000FF,
                          type: 0x267F99, function: 0x795E26)
        case .darkModern:
            EditorPalette(dark: true, background: 0x1F1F1F, foreground: 0xCCCCCC, gutter: 0x6E7681, selection: 0x264F78,
                          cursor: 0xAEAFAD, comment: 0x6A9955, string: 0xCE9178, number: 0xB5CEA8, keyword: 0x569CD6,
                          type: 0x4EC9B0, function: 0xDCDCAA)
        case .dracula:
            EditorPalette(dark: true, background: 0x282A36, foreground: 0xF8F8F2, gutter: 0x6272A4, selection: 0x44475A,
                          cursor: 0xF8F8F2, comment: 0x6272A4, string: 0xF1FA8C, number: 0xBD93F9, keyword: 0xFF79C6,
                          type: 0x8BE9FD, function: 0x50FA7B)
        case .oneDark:
            EditorPalette(dark: true, background: 0x282C34, foreground: 0xABB2BF, gutter: 0x495162, selection: 0x3E4451,
                          cursor: 0x528BFF, comment: 0x7F848E, string: 0x98C379, number: 0xD19A66, keyword: 0xC678DD,
                          type: 0xE5C07B, function: 0x61AFEF)
        case .monokai:
            EditorPalette(dark: true, background: 0x272822, foreground: 0xF8F8F2, gutter: 0x90908A, selection: 0x49483E,
                          cursor: 0xF8F8F0, comment: 0x88846F, string: 0xE6DB74, number: 0xAE81FF, keyword: 0xF92672,
                          type: 0x66D9EF, function: 0xA6E22E)
        case .githubDark:
            EditorPalette(dark: true, background: 0x0D1117, foreground: 0xE6EDF3, gutter: 0x6E7681, selection: 0x264F78,
                          cursor: 0x2F81F7, comment: 0x8B949E, string: 0xA5D6FF, number: 0x79C0FF, keyword: 0xFF7B72,
                          type: 0xFFA657, function: 0xD2A8FF)
        case .githubLight:
            EditorPalette(dark: false, background: 0xFFFFFF, foreground: 0x1F2328, gutter: 0x8C959F, selection: 0xB6E3FF,
                          cursor: 0x0969DA, comment: 0x6E7781, string: 0x0A3069, number: 0x0550AE, keyword: 0xCF222E,
                          type: 0x953800, function: 0x8250DF)
        case .nord:
            EditorPalette(dark: true, background: 0x2E3440, foreground: 0xD8DEE9, gutter: 0x4C566A, selection: 0x434C5E,
                          cursor: 0xD8DEE9, comment: 0x616E88, string: 0xA3BE8C, number: 0xB48EAD, keyword: 0x81A1C1,
                          type: 0x8FBCBB, function: 0x88C0D0)
        case .solarizedDark:
            EditorPalette(dark: true, background: 0x002B36, foreground: 0x839496, gutter: 0x586E75, selection: 0x274642,
                          cursor: 0xD30102, comment: 0x586E75, string: 0x2AA198, number: 0xD33682, keyword: 0x859900,
                          type: 0xCB4B16, function: 0x268BD2)
        case .solarizedLight:
            EditorPalette(dark: false, background: 0xFDF6E3, foreground: 0x657B83, gutter: 0x93A1A1, selection: 0xEEE8D5,
                          cursor: 0x657B83, comment: 0x93A1A1, string: 0x2AA198, number: 0xD33682, keyword: 0x859900,
                          type: 0xCB4B16, function: 0x268BD2)
        }
    }

    /// Automatic leaves the app's own look alone; any other theme also colors the app and sets light or dark.
    var themesApp: Bool { self != .automatic }

    static var current: EditorTheme {
        EditorTheme(rawValue: UserDefaults.standard.string(forKey: "editorTheme") ?? "") ?? .automatic
    }
}

/// The colors of one theme, as sRGB hex: the editor's, plus the sidebars, accent and terminal colors.
struct EditorPalette: Equatable {
    let dark: Bool
    let background, foreground, gutter, selection, cursor: UInt32
    let comment, string, number, keyword, type, function: UInt32
    var sidebar: UInt32 = 0
    var accent: UInt32 = 0
    /// the terminal's 16 ANSI colors
    var ansi: [UInt32] = []

    func ns(_ hex: UInt32) -> NSColor {
        NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }

    func color(_ kind: SyntaxTokens.Kind) -> NSColor {
        switch kind {
        case .comment: ns(comment)
        case .string: ns(string)
        case .number: ns(number)
        case .keyword: ns(keyword)
        case .type: ns(type)
        case .function: ns(function)
        }
    }

    /// a few swatches for the theme picker
    var swatches: [Color] { [background, keyword, string, function, type].map { Color(hex: $0) } }
}

extension View {
    /// The theme's color behind a pane (editor background, or the sidebar color for side columns and bars);
    /// nothing under Automatic, which keeps the system look.
    func themeBackground(sidebar: Bool = false) -> some View { modifier(ThemeBackground(sidebar: sidebar)) }
}

private struct ThemeBackground: ViewModifier {
    @AppStorage("editorTheme") private var theme: EditorTheme = .automatic
    let sidebar: Bool

    func body(content: Content) -> some View {
        if theme.themesApp {
            let p = theme.palette(dark: true)   // a fixed theme is the same in light and dark
            content.scrollContentBackground(.hidden).background(Color(hex: sidebar ? p.sidebar : p.background))
        } else {
            content
        }
    }
}

/// Syntax colors of an editor, as the layout manager's temporary attributes: drawn over the text's own
/// foreground, but not part of the text, so they never reach undo or the file.
@MainActor
enum SyntaxColoring {
    static func apply(_ tv: NSTextView, palette: EditorPalette, language: SyntaxTokens.Language?) {
        guard let lm = tv.layoutManager else { return }
        let length = (tv.string as NSString).length
        lm.removeTemporaryAttribute(.foregroundColor, forCharacterRange: NSRange(location: 0, length: length))
        guard let language else { return }
        for t in SyntaxTokens.tokens(tv.string, language: language) where t.location + t.length <= length {
            lm.addTemporaryAttribute(.foregroundColor, value: palette.color(t.kind),
                                     forCharacterRange: NSRange(location: t.location, length: t.length))
        }
    }
}

/// Menu of themes, for the editor's toolbar and the View menu.
struct EditorThemePicker: View {
    @AppStorage("editorTheme") private var theme: EditorTheme = .automatic

    var body: some View {
        Picker("Theme", selection: $theme) {
            ForEach(EditorTheme.allCases) { t in Text(t.title).tag(t) }
        }
    }
}

/// Five dots in the colors of a theme.
struct ThemeSwatches: View {
    let palette: EditorPalette

    var body: some View {
        HStack(spacing: 3) {
            ForEach(Array(palette.swatches.enumerated()), id: \.offset) { i, c in
                if i == 0 {
                    RoundedRectangle(cornerRadius: 3).fill(c).frame(width: 14, height: 14)
                        .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(.separator))
                } else {
                    Circle().fill(c).frame(width: 9, height: 9)
                }
            }
        }
    }
}
