import AppKit
import Combine
import Foundation

#if !DEBUG
import ApplicationServices
import Carbon
import CoreGraphics
#endif

public final class HistoryPanelViewModel: ObservableObject {
    @Published public var query: String = "" {
        didSet {
            selectedIndex = 0
            clearAIOutput()
        }
    }
    @Published public var category: ClipboardCategory = .all {
        didSet {
            selectedIndex = 0
            clearAIOutput()
        }
    }
    @Published public private(set) var selectedIndex: Int = 0
    @Published public var aiActionsVisible: Bool = false
    @Published public var selectedAIActionIndex: Int = 0
    @Published public var aiLoading: Bool = false
    @Published public var aiResult: String?
    @Published public var aiError: String?

    private let store: HistoryStore
    private let pasteboard: PasteboardClient
    private let aiService: AIServiceProtocol
    private let aiSettingsStore: AISettingsProviding

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
    }

    public var visibleItems: [ClipboardItem] {
        let items = (try? store.fetchAll()) ?? []
        return SearchService.search(items: items, query: query, category: category)
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
            selectedIndex = newIndex
            clearAIOutput()
        }
    }

    public func select(index: Int) {
        let maxIndex = max(visibleItems.count - 1, 0)
        let newIndex = min(max(index, 0), maxIndex)
        if newIndex != selectedIndex {
            selectedIndex = newIndex
            clearAIOutput()
        }
    }

    public func copySelected() throws {
        guard visibleItems.indices.contains(selectedIndex) else { return }
        try pasteboard.write(visibleItems[selectedIndex])
    }

    public func openAIActions() {
        guard let selectedItem, selectedItem.type == .text else {
            aiActionsVisible = true
            aiError = AIServiceError.unsupportedItem.localizedDescription
            aiResult = nil
            return
        }
        aiActionsVisible = true
        aiError = nil
    }

    public func closeAIActions() {
        aiActionsVisible = false
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
        aiResult = nil
        aiError = nil
        aiLoading = false
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
