import AppKit
#if !DEBUG
import ApplicationServices
#endif
import FCatCore
import SwiftUI
import UniformTypeIdentifiers
import Vision

final class KeyboardCommitTextView: NSTextView {
    var commit: (() -> Void)?
    var cancel: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        if (event.keyCode == 36 || event.keyCode == 76),
           !event.modifierFlags.contains(.shift) {
            commit?()
            return
        }
        switch event.keyCode {
        case 53:
            cancel?()
        default:
            super.keyDown(with: event)
        }
    }
}

final class BorderlessWindow: NSPanel {
    override var canBecomeKey: Bool { true }
    override func resignKey() {
        super.resignKey()
        if isVisible {
            DispatchQueue.main.async { self.orderOut(nil) }
        }
    }
}

private func statusBarCatImage() -> NSImage {
    let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
        NSColor.black.setFill()
        NSColor.black.setStroke()

        let head = NSBezierPath()
        head.move(to: NSPoint(x: 2.5, y: 10.5))
        head.line(to: NSPoint(x: 2.1, y: 16.6))
        head.line(to: NSPoint(x: 6.2, y: 14.1))
        head.curve(
            to: NSPoint(x: 11.8, y: 14.1),
            controlPoint1: NSPoint(x: 7.8, y: 14.8),
            controlPoint2: NSPoint(x: 10.2, y: 14.8)
        )
        head.line(to: NSPoint(x: 15.9, y: 16.6))
        head.line(to: NSPoint(x: 15.5, y: 10.5))
        head.curve(
            to: NSPoint(x: 9, y: 2.2),
            controlPoint1: NSPoint(x: 17.2, y: 5.8),
            controlPoint2: NSPoint(x: 13.5, y: 2.2)
        )
        head.curve(
            to: NSPoint(x: 2.5, y: 10.5),
            controlPoint1: NSPoint(x: 4.5, y: 2.2),
            controlPoint2: NSPoint(x: 0.8, y: 5.8)
        )
        head.close()
        head.fill()

        // Cut friendly eyes and a tiny muzzle out of the template silhouette.
        NSGraphicsContext.current?.compositingOperation = .clear
        NSBezierPath(ovalIn: NSRect(x: 5.1, y: 8.2, width: 1.8, height: 2.5)).fill()
        NSBezierPath(ovalIn: NSRect(x: 11.1, y: 8.2, width: 1.8, height: 2.5)).fill()
        NSBezierPath(ovalIn: NSRect(x: 8.25, y: 5.6, width: 1.5, height: 1.1)).fill()
        NSGraphicsContext.current?.compositingOperation = .sourceOver

        // Short whiskers remain legible at menu-bar size.
        let whiskers = NSBezierPath()
        whiskers.lineWidth = 0.8
        whiskers.lineCapStyle = .round
        whiskers.move(to: NSPoint(x: 3.7, y: 6.9))
        whiskers.line(to: NSPoint(x: 0.6, y: 7.7))
        whiskers.move(to: NSPoint(x: 3.6, y: 5.7))
        whiskers.line(to: NSPoint(x: 0.5, y: 5.2))
        whiskers.move(to: NSPoint(x: 14.3, y: 6.9))
        whiskers.line(to: NSPoint(x: 17.4, y: 7.7))
        whiskers.move(to: NSPoint(x: 14.4, y: 5.7))
        whiskers.line(to: NSPoint(x: 17.5, y: 5.2))
        whiskers.stroke()
        return true
    }
    image.isTemplate = true
    image.accessibilityDescription = "FCat"
    return image
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var historyWindow: NSWindow?
    private var settingsWindow: NSWindow?
    private var pinnedImageWindows: [UUID: PinnedImageWindowController] = [:]
    private var monitor: ClipboardMonitor?
    private let hotKeyManager = GlobalHotKeyManager()
    private var store: ClipboardStore?
    private var pasteboard: SystemPasteboardClient?
    private var settingsViewModel = SettingsViewModel()
    private let aiSettingsStore = AISettingsStore()
    private let aiService = AIService()

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupEditMenu()

        #if !DEBUG
        if !AXIsProcessTrusted() {
            AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary)
        }
        #endif
        do {
            let support = try appSupportDirectory()
            let assetStore = try ImageAssetStore(directory: support.appendingPathComponent("Images", isDirectory: true))
            let store = try ClipboardStore(databaseURL: support.appendingPathComponent("history.sqlite"), historyCountLimit: settingsViewModel.historyCountLimit)
            let pasteboard = SystemPasteboardClient()
            self.store = store
            self.pasteboard = pasteboard
            monitor = ClipboardMonitor(
                pasteboard: pasteboard,
                sink: store,
                imageSaver: assetStore.savePNGData,
                sourceAppNameProvider: {
                    guard let app = NSWorkspace.shared.frontmostApplication,
                          app.bundleIdentifier != Bundle.main.bundleIdentifier else { return nil }
                    return app.localizedName
                }
            )
            monitor?.start()
            createStatusItem()
            if let hotKey = settingsViewModel.hotKey {
                try register(hotKey)
            } else {
                openSettings()
            }
        } catch {
            showError("Failed to start FCat: \(error)")
        }
    }

    private func setupEditMenu() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu()
        appMenuItem.submenu = appMenu
        appMenu.addItem(NSMenuItem(title: "Quit FCat", action: #selector(quit), keyEquivalent: "q"))

        let editMenuItem = NSMenuItem()
        mainMenu.addItem(editMenuItem)
        let editMenu = NSMenu(title: "Edit")
        editMenuItem.submenu = editMenu
        editMenu.addItem(NSMenuItem(title: "Copy", action: NSSelectorFromString("copy:"), keyEquivalent: "c"))
        editMenu.addItem(NSMenuItem(title: "Paste", action: NSSelectorFromString("paste:"), keyEquivalent: "v"))
        editMenu.addItem(NSMenuItem(title: "Cut", action: NSSelectorFromString("cut:"), keyEquivalent: "x"))
        editMenu.addItem(NSMenuItem(title: "Select All", action: NSSelectorFromString("selectAll:"), keyEquivalent: "a"))
        editMenu.addItem(NSMenuItem(title: "Undo", action: NSSelectorFromString("undo:"), keyEquivalent: "z"))

        NSApp.mainMenu = mainMenu
    }

    private func createStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            button.image = statusBarCatImage()
            button.imagePosition = .imageOnly
            button.setAccessibilityLabel("FCat Clipboard History")
        }

        let menu = NSMenu()
        let openHistoryItem = NSMenuItem(title: "Open History", action: #selector(openHistory), keyEquivalent: "")
        openHistoryItem.target = self
        let settingsItem = NSMenuItem(title: "Settings", action: #selector(openSettings), keyEquivalent: "")
        settingsItem.target = self
        let clearItem = NSMenuItem(title: "Clear Non-Favorites", action: #selector(clearNonFavorites), keyEquivalent: "")
        clearItem.target = self
        let quitItem = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self

        menu.addItem(openHistoryItem)
        menu.addItem(settingsItem)
        menu.addItem(clearItem)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(quitItem)
        item.menu = menu
        statusItem = item
    }

    @objc private func openHistory() {
        DispatchQueue.main.async { [weak self] in self?.doOpenHistory() }
    }

    private func doOpenHistory() {
        guard let store, let pasteboard else { return }
        if let historyWindow, historyWindow.isVisible {
            dismissHistory()
            return
        }

        let viewModel = HistoryPanelViewModel(store: store, pasteboard: pasteboard, aiService: aiService, aiSettingsStore: aiSettingsStore)
        let view = HistoryPanelView(
            viewModel: viewModel,
            close: { [weak self] in self?.dismissHistory() },
            pinImage: { [weak self] item in self?.pinImage(item) },
            performContextAction: { [weak self] action, item in
                self?.performContextAction(action, on: item)
            }
        )
        let window = BorderlessWindow(
            contentRect: NSRect(x: 0, y: 0, width: 700, height: 520),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        window.identifier = NSUserInterfaceItemIdentifier("FCatHistoryWindow")
        window.contentView = NSHostingView(rootView: view)
        window.backgroundColor = .clear
        window.isOpaque = false
        window.isMovableByWindowBackground = true
        window.hasShadow = true
        window.isFloatingPanel = true
        window.hidesOnDeactivate = false
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        positionHistoryWindow(window)
        historyWindow = window
        // Let NSHostingView finish mounting its AppKit-backed List before
        // changing key-window state. Calling makeKey synchronously here can
        // re-enter NSTableView while SwiftUI is still building its delegate.
        DispatchQueue.main.async { [weak self, weak window] in
            guard let self, let window else { return }
            self.focusHistoryWindow(window)
        }
    }

    private func focusHistoryWindow(_ window: NSWindow) {
        // A non-activating panel can become key without making FCat the active
        // application. This is essential while the foreground application owns
        // Secure Event Input (for example an SSH or browser password field).
        window.orderFrontRegardless()
        window.makeKey()
    }

    private func dismissHistory() {
        historyWindow?.orderOut(nil)
    }

    private func positionHistoryWindow(_ window: NSWindow) {
        // Put the panel on the display where the pointer (and normally the
        // invoking app) currently is, including when that display is full-screen.
        let pointer = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(pointer, $0.frame, false) }) else {
            window.center()
            return
        }
        let visibleFrame = screen.visibleFrame
        let origin = NSPoint(
            x: visibleFrame.midX - window.frame.width / 2,
            y: visibleFrame.midY - window.frame.height / 2
        )
        window.setFrameOrigin(origin)
    }

    @objc private func openSettings() {
        DispatchQueue.main.async { [weak self] in self?.doOpenSettings() }
    }

    private func doOpenSettings() {
        let view = SettingsView(viewModel: settingsViewModel, saveHotKey: { [weak self] hotKey in
            if hotKey.keyCode == 0 && hotKey.modifiers == 0 {
                self?.hotKeyManager.unregister()
            } else {
                do { try self?.register(hotKey) }
                catch { self?.showError("Shortcut registration failed. Choose another shortcut.") }
            }
        }, saveHistoryCountLimit: { [weak self] limit in
            try? self?.store?.setHistoryCountLimit(limit)
        })
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 460), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.contentView = NSHostingView(rootView: view)
        window.title = "FCat Settings"
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow = window
    }

    @objc private func clearNonFavorites() {
        try? store?.clearNonFavorites()
    }

    @objc private func quit() {
        monitor?.stop()
        NSApplication.shared.terminate(nil)
    }

    private func register(_ hotKey: HotKey) throws {
        try hotKeyManager.register(hotKey) { [weak self] in self?.openHistory() }
    }

    private func pinImage(_ item: ClipboardItem) {
        guard item.type == .image,
              let path = item.assetPath,
              let controller = PinnedImageWindowController(imagePath: path, title: item.previewTitle) else {
            showError("The selected image could not be opened.")
            return
        }

        controller.onClose = { [weak self] id in
            self?.pinnedImageWindows.removeValue(forKey: id)
        }
        pinnedImageWindows[controller.id] = controller
        controller.showWindow(nil)
        controller.window?.orderFrontRegardless()
        historyWindow?.orderOut(nil)
    }

    private func performContextAction(_ action: ClipboardContextAction, on item: ClipboardItem) {
        do {
            switch action {
            case .copy:
                try pasteboard?.write(item)
            case .paste:
                try pasteboard?.write(item)
                pasteFromClipboard()
            case .pastePlainText:
                try pasteboard?.writeText(item.contentText ?? "")
                pasteFromClipboard()
            case .editAndCopy:
                editAndCopy(item.contentText ?? "")
            case .pinImage:
                pinImage(item)
            case .saveImage:
                try saveImage(item)
            case .recognizeText:
                recognizeText(in: item)
            case .compressImage:
                try compressImage(item)
            case .revealInFinder:
                revealInFinder(item)
            case .copyFilePaths:
                try pasteboard?.writeText(item.contentText ?? "")
            case .copyFileNames:
                let names = filePaths(in: item).map { URL(fileURLWithPath: $0).lastPathComponent }
                try pasteboard?.writeText(names.joined(separator: "\n"))
            }
        } catch {
            showError(error.localizedDescription)
        }
    }

    private func pasteFromClipboard() {
        historyWindow?.orderOut(nil)
        NSApp.hide(nil)
        #if !DEBUG
        guard HistoryPanelViewModel.isAccessibilityTrusted(prompt: true) else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            let source = CGEventSource(stateID: .hidSystemState)
            let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true)
            let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false)
            keyDown?.flags = .maskCommand
            keyUp?.flags = .maskCommand
            keyDown?.post(tap: .cghidEventTap)
            keyUp?.post(tap: .cghidEventTap)
        }
        #endif
    }

    private func editAndCopy(_ originalText: String) {
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 480, height: 240))
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder
        let textView = KeyboardCommitTextView(frame: scrollView.bounds)
        textView.isRichText = false
        textView.font = .systemFont(ofSize: 13)
        textView.string = originalText
        scrollView.documentView = textView

        let alert = NSAlert()
        alert.messageText = "Edit Clipboard Text"
        alert.informativeText = "Enter to copy · Shift+Enter for a new line · Esc to cancel"
        alert.accessoryView = scrollView
        alert.addButton(withTitle: "Copy")
        alert.addButton(withTitle: "Cancel")
        let copyEditedText = { [weak self, weak textView] in
            guard let text = textView?.string else { return }
            do { try self?.pasteboard?.writeText(text) }
            catch { self?.showError(error.localizedDescription) }
        }
        textView.commit = { [weak alert] in
            NSApp.abortModal()
            alert?.window.orderOut(nil)
            copyEditedText()
        }
        textView.cancel = { [weak alert] in
            NSApp.abortModal()
            alert?.window.orderOut(nil)
        }
        alert.window.initialFirstResponder = textView
        if alert.runModal() == .alertFirstButtonReturn {
            copyEditedText()
        }
    }

    private func saveImage(_ item: ClipboardItem) throws {
        guard let path = item.assetPath else { throw ContextActionError.imageUnavailable }
        let sourceURL = URL(fileURLWithPath: path)
        let panel = NSSavePanel()
        panel.title = "Save Clipboard Image"
        panel.nameFieldStringValue = "Clipboard Image.png"
        panel.allowedContentTypes = [.png]
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        try FileManager.default.copyItemReplacingExisting(at: sourceURL, to: destination)
    }

    private func compressImage(_ item: ClipboardItem) throws {
        guard let path = item.assetPath,
              let image = NSImage(contentsOfFile: path),
              let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let data = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.7]) else {
            throw ContextActionError.imageUnavailable
        }
        let panel = NSSavePanel()
        panel.title = "Save Compressed Image"
        panel.nameFieldStringValue = "Clipboard Image.jpg"
        panel.allowedContentTypes = [.jpeg]
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        try data.write(to: destination, options: .atomic)
    }

    private func recognizeText(in item: ClipboardItem) {
        guard let path = item.assetPath else {
            showError(ContextActionError.imageUnavailable.localizedDescription)
            return
        }
        let request = VNRecognizeTextRequest { [weak self] request, error in
            let text = (request.results as? [VNRecognizedTextObservation])?
                .compactMap { $0.topCandidates(1).first?.string }
                .joined(separator: "\n") ?? ""
            DispatchQueue.main.async {
                if let error { self?.showError(error.localizedDescription); return }
                guard !text.isEmpty else {
                    self?.showError("No text was recognized in this image.")
                    return
                }
                do { try self?.pasteboard?.writeText(text) }
                catch { self?.showError(error.localizedDescription) }
            }
        }
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do { try VNImageRequestHandler(url: URL(fileURLWithPath: path)).perform([request]) }
            catch { DispatchQueue.main.async { self?.showError(error.localizedDescription) } }
        }
    }

    private func revealInFinder(_ item: ClipboardItem) {
        let urls = filePaths(in: item).map { URL(fileURLWithPath: $0) }
        guard !urls.isEmpty else { showError("No file path is available."); return }
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }

    private func filePaths(in item: ClipboardItem) -> [String] {
        (item.contentText ?? "").split(separator: "\n").map(String.init)
    }

    private func appSupportDirectory() throws -> URL {
        let base = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let directory = base.appendingPathComponent("FCat", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func showError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = message
        alert.runModal()
    }
}

private enum ContextActionError: LocalizedError {
    case imageUnavailable

    var errorDescription: String? {
        "The selected image could not be opened."
    }
}

private extension FileManager {
    func copyItemReplacingExisting(at source: URL, to destination: URL) throws {
        if fileExists(atPath: destination.path) { try removeItem(at: destination) }
        try copyItem(at: source, to: destination)
    }
}
