import AppKit
#if !DEBUG
import ApplicationServices
#endif
import FCatCore
import SwiftUI

final class BorderlessWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override func resignKey() {
        super.resignKey()
        if isVisible {
            DispatchQueue.main.async { self.orderOut(nil) }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var historyWindow: NSWindow?
    private var settingsWindow: NSWindow?
    private var monitor: ClipboardMonitor?
    private let hotKeyManager = GlobalHotKeyManager()
    private var store: ClipboardStore?
    private var pasteboard: SystemPasteboardClient?
    private var settingsViewModel = SettingsViewModel()
    private let aiSettingsStore = AISettingsStore()
    private let aiService = AIService()

    func applicationDidFinishLaunching(_ notification: Notification) {
        #if !DEBUG
        if !AXIsProcessTrusted() {
            AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary)
        }
        #endif
        do {
            let support = try appSupportDirectory()
            let assetStore = try ImageAssetStore(directory: support.appendingPathComponent("Images", isDirectory: true))
            let store = try ClipboardStore(databaseURL: support.appendingPathComponent("history.sqlite"))
            let pasteboard = SystemPasteboardClient()
            self.store = store
            self.pasteboard = pasteboard
            monitor = ClipboardMonitor(pasteboard: pasteboard, sink: store, imageSaver: assetStore.savePNGData)
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

    private func createStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "F"

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
        guard let store, let pasteboard else { return }
        if let historyWindow, historyWindow.isVisible {
            historyWindow.orderOut(nil)
            return
        }

        let viewModel = HistoryPanelViewModel(store: store, pasteboard: pasteboard, aiService: aiService, aiSettingsStore: aiSettingsStore)
        let view = HistoryPanelView(viewModel: viewModel) { [weak self] in self?.historyWindow?.orderOut(nil) }
        let window = BorderlessWindow(contentRect: NSRect(x: 0, y: 0, width: 700, height: 520), styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = NSHostingView(rootView: view)
        window.backgroundColor = .clear
        window.isOpaque = false
        window.isMovableByWindowBackground = true
        window.hasShadow = true
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        historyWindow = window
    }

    @objc private func openSettings() {
        let view = HotKeyRecorderView(viewModel: settingsViewModel) { [weak self] hotKey in
            if hotKey.keyCode == 0 && hotKey.modifiers == 0 {
                self?.hotKeyManager.unregister()
            } else {
                do { try self?.register(hotKey) }
                catch { self?.showError("Shortcut registration failed. Choose another shortcut.") }
            }
        }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 520), styleMask: [.titled, .closable], backing: .buffered, defer: false)
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
