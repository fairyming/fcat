import AppKit

final class PinnedImageWindowController: NSWindowController, NSWindowDelegate {
    let id = UUID()
    var onClose: ((UUID) -> Void)?

    init?(imagePath: String, title: String) {
        guard let image = NSImage(contentsOfFile: imagePath) else { return nil }

        let size = Self.initialSize(for: image.size)
        let imageView = NSImageView(frame: NSRect(origin: .zero, size: size))
        imageView.image = image
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.imageAlignment = .alignCenter

        let window = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = title.isEmpty ? "Pinned Image" : title
        window.contentView = imageView
        window.level = .floating
        window.collectionBehavior = [.moveToActiveSpace]
        window.hidesOnDeactivate = false
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 160, height: 120)
        window.contentAspectRatio = image.size
        window.center()

        super.init(window: window)
        window.delegate = self
    }

    required init?(coder: NSCoder) {
        nil
    }

    func windowWillClose(_ notification: Notification) {
        onClose?(id)
    }

    private static func initialSize(for imageSize: NSSize) -> NSSize {
        guard imageSize.width > 0, imageSize.height > 0 else {
            return NSSize(width: 480, height: 360)
        }

        let maximum = NSSize(width: 640, height: 520)
        let minimumScale = min(min(maximum.width / imageSize.width, maximum.height / imageSize.height), 1)
        let scaled = NSSize(width: imageSize.width * minimumScale, height: imageSize.height * minimumScale)
        if scaled.width >= 240, scaled.height >= 160 { return scaled }

        let expansion = max(240 / scaled.width, 160 / scaled.height)
        return NSSize(width: scaled.width * expansion, height: scaled.height * expansion)
    }
}
