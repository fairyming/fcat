import AppKit
import Combine
import Foundation

#if !DEBUG
import ApplicationServices
import Carbon
import CoreGraphics
#endif

public final class HistoryPanelViewModel: ObservableObject {
    @Published public var query: String = "" { didSet { selectedIndex = 0 } }
    @Published public var category: ClipboardCategory = .all { didSet { selectedIndex = 0 } }
    @Published public private(set) var selectedIndex: Int = 0

    private let store: HistoryStore
    private let pasteboard: PasteboardClient

    public init(store: HistoryStore, pasteboard: PasteboardClient) {
        self.store = store
        self.pasteboard = pasteboard
    }

    public var visibleItems: [ClipboardItem] {
        let items = (try? store.fetchAll()) ?? []
        return SearchService.search(items: items, query: query, category: category)
    }

    public func moveSelection(delta: Int) {
        let maxIndex = max(visibleItems.count - 1, 0)
        selectedIndex = min(max(selectedIndex + delta, 0), maxIndex)
    }

    public func select(index: Int) {
        let maxIndex = max(visibleItems.count - 1, 0)
        selectedIndex = min(max(index, 0), maxIndex)
    }

    public func copySelected() throws {
        guard visibleItems.indices.contains(selectedIndex) else { return }
        try pasteboard.write(visibleItems[selectedIndex])
    }

    #if !DEBUG
    public static func isAccessibilityTrusted(prompt: Bool = false) -> Bool {
        if prompt {
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
            return AXIsProcessTrustedWithOptions(options)
        }
        return AXIsProcessTrusted()
    }

    public func pasteSelected() throws {
        try copySelected()
    }

    public func simulatePaste() {
        let source = CGEventSource(stateID: .hidSystemState)
        let vKey: CGKeyCode = CGKeyCode(kVK_ANSI_V)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: false)
        keyDown?.flags = CGEventFlags.maskCommand
        keyUp?.flags = CGEventFlags.maskCommand
        keyDown?.post(tap: CGEventTapLocation.cghidEventTap)
        keyUp?.post(tap: CGEventTapLocation.cghidEventTap)
    }
    #endif

    public func toggleFavoriteSelected() throws {
        guard visibleItems.indices.contains(selectedIndex) else { return }
        try store.toggleFavorite(id: visibleItems[selectedIndex].id)
        objectWillChange.send()
    }

    public func deleteSelected() throws {
        guard visibleItems.indices.contains(selectedIndex) else { return }
        try store.delete(id: visibleItems[selectedIndex].id)
        selectedIndex = min(selectedIndex, max(visibleItems.count - 1, 0))
        objectWillChange.send()
    }

    public func clearNonFavorites() throws {
        try store.clearNonFavorites()
        selectedIndex = 0
        objectWillChange.send()
    }
}
