import AppKit
import Combine
import Foundation

#if !DEBUG
import ApplicationServices
import Carbon
import CoreGraphics
#endif

public final class HistoryPanelViewModel: ObservableObject {
    private var storedQuery = ""
    public var query: String {
        get { storedQuery }
        set {
            guard newValue != storedQuery else { return }
            objectWillChange.send()
            storedQuery = newValue
            refreshVisibleItems()
            if selectedIndex != 0 { selectedIndex = 0 }
            clearAIOutput()
        }
    }

    private var storedCategory: ClipboardCategory = .all
    public var category: ClipboardCategory {
        get { storedCategory }
        set {
            guard newValue != storedCategory else { return }
            objectWillChange.send()
            storedCategory = newValue
            refreshVisibleItems()
            if selectedIndex != 0 { selectedIndex = 0 }
            clearAIOutput()
        }
    }
    public private(set) var selectedIndex: Int = 0
    @Published public var actionsVisible: Bool = false
    @Published public var selectedAIActionIndex: Int = 0
    @Published public var aiLoading: Bool = false
    @Published public var aiResult: String?
    @Published public var aiError: String?
    public private(set) var visibleItems: [ClipboardItem] = []

    private let store: HistoryStore
    private let pasteboard: PasteboardClient
    private let aiService: AIServiceProtocol
    private let aiSettingsStore: AISettingsProviding
    private var allItems: [ClipboardItem] = []

    public init(
        store: HistoryStore,
        pasteboard: PasteboardClient,
        aiService: AIServiceProtocol = AIService(),
        aiSettingsStore: AISettingsProviding = AISettingsStore()
    ) {
        self.store = store
        self.pasteboard = pasteboard
        self.aiService = aiService
        self.aiSettingsStore = aiSettingsStore
        reloadItems(selecting: nil, notify: false)
    }

    public var aiActions: [AIAction] { AIAction.builtIn }

    public var selectedItem: ClipboardItem? {
        guard visibleItems.indices.contains(selectedIndex) else { return nil }
        return visibleItems[selectedIndex]
    }

    public var selectedAIAction: AIAction {
        aiActions[min(max(selectedAIActionIndex, 0), aiActions.count - 1)]
    }

    public func moveSelection(delta: Int) {
        let maxIndex = max(visibleItems.count - 1, 0)
        let newIndex = min(max(selectedIndex + delta, 0), maxIndex)
        if newIndex != selectedIndex {
            objectWillChange.send()
            selectedIndex = newIndex
            clearAIOutput()
        }
    }

    public func select(index: Int) {
        let maxIndex = max(visibleItems.count - 1, 0)
        let newIndex = min(max(index, 0), maxIndex)
        if newIndex != selectedIndex {
            objectWillChange.send()
            selectedIndex = newIndex
            clearAIOutput()
        }
    }

    public func moveCategory(delta: Int) {
        let categories = ClipboardCategory.allCases
        guard let current = categories.firstIndex(of: category) else { return }
        let next = min(max(current + delta, 0), categories.count - 1)
        guard next != current else { return }
        category = categories[next]
    }

    public func copySelected() throws {
        guard visibleItems.indices.contains(selectedIndex) else { return }
        try pasteboard.write(visibleItems[selectedIndex])
    }

    public func openActions() {
        actionsVisible = true
        aiError = nil
    }

    public func closeActions() {
        actionsVisible = false
    }

    public func moveAIActionSelection(delta: Int) {
        let maxIndex = max(aiActions.count - 1, 0)
        selectedAIActionIndex = min(max(selectedAIActionIndex + delta, 0), maxIndex)
    }

    @MainActor
    public func runSelectedAIAction() async {
        guard !aiLoading, let selectedItem else { return }
        aiLoading = true
        aiResult = nil
        aiError = nil

        if selectedAIAction.id == AIAction.formatJSON.id {
            runSelectedAIActionSynchronouslyForLocalActions()
            aiLoading = false
            return
        }

        do {
            aiResult = try await aiService.run(action: selectedAIAction, item: selectedItem, settings: aiSettingsStore.loadSettings())
        } catch {
            aiError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        aiLoading = false
    }

    public func runSelectedAIActionSynchronouslyForLocalActions() {
        guard let selectedItem, let text = selectedItem.contentText else { return }
        if selectedAIAction.id == AIAction.formatJSON.id {
            do { aiResult = try JSONFormatter.format(text) }
            catch { aiError = "Selected text is not valid JSON." }
        }
    }

    public func copyAIResult() throws {
        guard let aiResult else { return }
        try pasteboard.writeText(aiResult)
    }

    public func clearAIOutput() {
        if aiResult != nil { aiResult = nil }
        if aiError != nil { aiError = nil }
        if aiLoading { aiLoading = false }
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
        try toggleFavorite(id: visibleItems[selectedIndex].id)
    }

    public func toggleFavorite(id: UUID) throws {
        guard visibleItems.contains(where: { $0.id == id }) else { return }
        try store.toggleFavorite(id: id)
        reloadItems(selecting: id)
    }

    public func deleteSelected() throws {
        guard visibleItems.indices.contains(selectedIndex) else { return }
        try store.delete(id: visibleItems[selectedIndex].id)
        let nextIndex = selectedIndex
        reloadItems()
        selectedIndex = min(nextIndex, max(visibleItems.count - 1, 0))
    }

    public func clearNonFavorites() throws {
        try store.clearNonFavorites()
        reloadItems()
        selectedIndex = 0
    }

    public func reloadItems() {
        reloadItems(selecting: selectedItem?.id)
    }

    private func reloadItems(selecting selectedID: UUID? = nil, notify: Bool = true) {
        if notify { objectWillChange.send() }
        allItems = (try? store.fetchAll()) ?? []
        refreshVisibleItems()
        if let selectedID,
           let index = visibleItems.firstIndex(where: { $0.id == selectedID }) {
            selectedIndex = index
        } else {
            selectedIndex = min(selectedIndex, max(visibleItems.count - 1, 0))
        }
    }

    private func refreshVisibleItems() {
        visibleItems = SearchService.search(items: allItems, query: query, category: category)
    }
}
