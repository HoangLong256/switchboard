import SwiftUI

/// Monospaced text with line numbers. Lazy, so only the visible lines are laid out (large files stay fast);
/// long lines scroll sideways instead of wrapping, like an editor.
struct CodeTextView: View {
    let text: String

    private var lines: [Substring] { text.split(separator: "\n", omittingEmptySubsequences: false) }

    var body: some View {
        let lines = lines
        let gutter = CGFloat(String(lines.count).count) * 7.5 + 14
        ScrollView([.vertical, .horizontal]) {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(lines.indices, id: \.self) { i in
                    HStack(alignment: .firstTextBaseline, spacing: 0) {
                        Text("\(i + 1)")
                            .foregroundStyle(.tertiary)
                            .frame(width: gutter, alignment: .trailing)
                            .padding(.trailing, 12)
                        Text(lines[i].isEmpty ? " " : String(lines[i]))
                            .fixedSize(horizontal: true, vertical: false)
                    }
                }
            }
            .font(.system(size: 12, design: .monospaced))
            .textSelection(.enabled)
            .padding(.vertical, 8).padding(.trailing, 16)
        }
        // lazily laid out lines change the content width; keep the start at the left edge
        .defaultScrollAnchor(.topLeading)
    }
}
