import AppKit
import SwiftUI

/// An image file in the editor. AppKit's image view plays animated GIFs (SwiftUI's `Image` shows only the
/// first frame). Large images shrink to fit; "Actual Size" shows them pixel for pixel, with scrolling.
struct ImagePreview: View {
    let path: String
    @State private var image: NSImage?
    @State private var failed = false
    @State private var actualSize = false

    var body: some View {
        Group {
            if let image {
                VStack(spacing: 0) {
                    if actualSize {
                        ScrollView([.horizontal, .vertical]) {
                            AnimatedImage(image: image).frame(width: image.size.width, height: image.size.height).padding(20)
                        }
                    } else {
                        AnimatedImage(image: image).padding(20)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    Divider()
                    caption(image)
                }
            } else if failed {
                ContentUnavailableView("Can't show this image.", systemImage: "photo")
            } else {
                ProgressView().controlSize(.small)
            }
        }
        .task(id: path) { await load() }
    }

    private func caption(_ image: NSImage) -> some View {
        HStack(spacing: 10) {
            Text(Self.describe(image, path: path)).font(.caption).foregroundStyle(.secondary).monospacedDigit()
            Spacer()
            Toggle("Actual Size", isOn: $actualSize).toggleStyle(.button).controlSize(.small)
                .help(actualSize ? "Fit the image in the window" : "Show the image pixel for pixel")
        }
        .padding(.horizontal, 12).padding(.vertical, 5)
    }

    private func load() async {
        failed = false
        let path = path
        // decoding a large image or a long GIF takes a moment; keep it off the main thread
        let data = await Task.detached { FileManager.default.contents(atPath: path) }.value
        guard let data, let img = NSImage(data: data) else { image = nil; failed = true; return }
        image = img
    }

    /// "480 × 270 · GIF · 36 frames"
    static func describe(_ image: NSImage, path: String) -> String {
        let rep = image.representations.first
        let w = rep?.pixelsWide ?? Int(image.size.width), h = rep?.pixelsHigh ?? Int(image.size.height)
        var parts = ["\(w) × \(h)", (path as NSString).pathExtension.uppercased()]
        if let bitmap = rep as? NSBitmapImageRep,
           let frames = bitmap.value(forProperty: .frameCount) as? Int, frames > 1 {
            parts.append("\(frames) frames")
        }
        return parts.joined(separator: " · ")
    }
}

/// NSImageView with animation on, scaled down proportionally (never up).
private struct AnimatedImage: NSViewRepresentable {
    let image: NSImage

    func makeNSView(context: Context) -> NSImageView {
        let v = NSImageView()
        v.animates = true
        v.imageScaling = .scaleProportionallyDown
        v.imageAlignment = .alignCenter
        v.isEditable = false
        // let SwiftUI size it: don't insist on the image's own size
        v.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        v.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        v.image = image
        return v
    }

    func updateNSView(_ v: NSImageView, context: Context) {
        if v.image !== image { v.image = image }
    }
}
