import Carbon
import AppKit
import SwiftUI

public enum ClipboardContextAction {
    case copy
    case paste
    case pastePlainText
    case editAndCopy
    case pinImage
    case saveImage
    case recognizeText
    case compressImage
    case revealInFinder
    case copyFilePaths
    case copyFileNames
}

private enum ActionMenuKind {
    case clipboard(ClipboardContextAction)
    case ai(Int)
}

private struct ActionMenuEntry: Identifiable {
    let id: String
    let title: String
    let kind: ActionMenuKind
}

public struct HistoryPanelView: View {
    @ObservedObject private var viewModel: HistoryPanelViewModel
    @FocusState private var searchFocused: Bool
    @State private var keyMonitor: Any?
    @State private var selectedActionIndex = 0
    private let close: () -> Void
    private let pinImage: (ClipboardItem) -> Void
    private let performContextAction: (ClipboardContextAction, ClipboardItem) -> Void

    public init(
        viewModel: HistoryPanelViewModel,
        close: @escaping () -> Void,
        pinImage: @escaping (ClipboardItem) -> Void = { _ in },
        performContextAction: @escaping (ClipboardContextAction, ClipboardItem) -> Void = { _, _ in }
    ) {
        self.viewModel = viewModel
        self.close = close
        self.pinImage = pinImage
        self.performContextAction = performContextAction
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Top bar: search + category
            VStack(spacing: 8) {
                TextField("Search clipboard history", text: $viewModel.query)
                    .textFieldStyle(.roundedBorder)
                    .focused($searchFocused)

                if viewModel.actionsVisible {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(Array(actionMenuEntries.enumerated()), id: \.element.id) { index, entry in
                                HStack {
                                    Text(entry.title)
                                    Spacer()
                                    if index == selectedActionIndex { Text("\u{21A9}") }
                                }
                                .font(.system(size: 13))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(index == selectedActionIndex ? Color.accentColor.opacity(0.18) : Color.clear)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    selectedActionIndex = index
                                    runSelectedMenuAction()
                                }
                            }
                        }
                    }
                    .frame(maxHeight: 220)
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color(NSColor.controlBackgroundColor)))
                }
            }
            .padding(12)

            Divider()

            // Left-right split
            HSplitView {
                // Left: item list
                ScrollViewReader { scrollProxy in
                    List(Array(viewModel.visibleItems.enumerated()), id: \.element.id) { index, item in
                        HStack(spacing: 8) {
                            Text(icon(for: item))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(width: 16)
                            Text(item.previewTitle)
                                .lineLimit(1)
                                .font(.system(size: 13))
                            Spacer()
                            Text(item.isFavorite ? "\u{2605}" : "\u{2606}")
                                .foregroundStyle(item.isFavorite ? .yellow : .secondary)
                                .font(.system(size: 14))
                                .onTapGesture { try? viewModel.toggleFavoriteSelected() }
                        }
                        .padding(.vertical, 3)
                        .padding(.horizontal, 6)
                        .background(index == viewModel.selectedIndex ? Color.accentColor.opacity(0.18) : Color.clear)
                        .contentShape(Rectangle())
                        .id(index)
                        .onTapGesture { viewModel.select(index: index) }
                    }
                    .frame(minWidth: 220)
                    .onChange(of: viewModel.selectedIndex) { newIndex in
                        withAnimation(.easeInOut(duration: 0.12)) {
                            scrollProxy.scrollTo(newIndex, anchor: .center)
                        }
                    }
                }

                // Right: detail preview
                if viewModel.visibleItems.indices.contains(viewModel.selectedIndex) {
                    let selectedItem = viewModel.visibleItems[viewModel.selectedIndex]
                    Group {
                        if viewModel.aiLoading {
                            Text("Running AI action\u{2026}")
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else if let aiError = viewModel.aiError {
                            Text(aiError)
                                .foregroundStyle(.red)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                                .padding(16)
                        } else if let aiResult = viewModel.aiResult {
                            ScrollView {
                                Text(aiResult)
                                    .font(.system(size: 13))
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(16)
                            }
                        } else {
                            ScrollView {
                                VStack(alignment: .leading, spacing: 12) {
                                    if selectedItem.type == .image, let assetPath = selectedItem.assetPath {
                                        if let image = NSImage(contentsOfFile: assetPath) {
                                            Image(nsImage: image)
                                                .resizable()
                                                .aspectRatio(contentMode: .fit)
                                                .frame(maxHeight: .infinity)
                                            Button("Pin on Top") {
                                                pinImage(selectedItem)
                                            }
                                            .keyboardShortcut("p", modifiers: .command)
                                        } else {
                                            Text("Image not found")
                                                .foregroundStyle(.secondary)
                                        }
                                    } else if let content = selectedItem.contentText {
                                        Text(content)
                                            .font(.system(size: 13))
                                            .textSelection(.enabled)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    } else {
                                        Text("No content")
                                            .foregroundStyle(.secondary)
                                    }

                                    if let source = selectedItem.sourceAppName {
                                        HStack {
                                            Text("Source:")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                            Text(source)
                                                .font(.caption)
                                        }
                                    }
                                }
                                .padding(16)
                            }
                        }
                    }
                    .frame(minWidth: 300)
                } else {
                    Text("No item selected")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }

            Divider()

            // Bottom: shortcuts hint
            HStack(spacing: 8) {
                #if DEBUG
                Text("Enter = copy  |  \u{2191}\u{2193} = select  |  \u{2318}D = favorite  |  \u{2318}\u{232B} = delete  |  Esc = close  |  Tab/\u{2318}K = actions")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                #else
                Text("Enter = paste  |  \u{2191}\u{2193} = select  |  \u{2318}D = favorite  |  \u{2318}\u{232B} = delete  |  Esc = close  |  Tab/\u{2318}K = actions")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                #endif
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
        .frame(width: 700, height: 520)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(NSColor.windowBackgroundColor)))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .onAppear { searchFocused = true; installKeyMonitor() }
        .onDisappear { removeKeyMonitor() }
        .onChange(of: viewModel.selectedItem?.id) { _ in selectedActionIndex = 0 }
    }

    private func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let keyCode = Int(event.keyCode)
            let modifiers = event.modifierFlags

            // Tab / Cmd+K toggles actions for the selected content type.
            if keyCode == kVK_Tab || (keyCode == kVK_ANSI_K && modifiers.contains(.command)) {
                if viewModel.actionsVisible { viewModel.closeActions() }
                else {
                    selectedActionIndex = 0
                    viewModel.openActions()
                }
                return nil
            }

            // Arrow keys: navigate AI actions when panel open, clipboard items otherwise
            if keyCode == kVK_UpArrow {
                if viewModel.actionsVisible {
                    moveActionSelection(delta: -1)
                } else {
                    viewModel.moveSelection(delta: -1)
                }
                return nil
            }

            if keyCode == kVK_DownArrow {
                if viewModel.actionsVisible {
                    moveActionSelection(delta: 1)
                } else {
                    viewModel.moveSelection(delta: 1)
                }
                return nil
            }

            // Cmd+C copies AI result
            if viewModel.aiResult != nil && keyCode == kVK_ANSI_C && modifiers.contains(.command) {
                try? viewModel.copyAIResult()
                return nil
            }

            // Enter: AI result takes priority over running AI action
            if keyCode == kVK_Return && modifiers.isDisjoint(with: [.command, .option, .control, .shift]) {
                if viewModel.aiResult != nil {
                    try? viewModel.copyAIResult()
                    close()
                    NSApp.hide(nil)
                    #if !DEBUG
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        viewModel.simulatePaste()
                    }
                    #endif
                    return nil
                }

                // Enter runs the selected contextual or AI action.
                if viewModel.actionsVisible {
                    runSelectedMenuAction()
                    return nil
                }

                // Normal copy/paste selected clipboard item
                #if DEBUG
                try? viewModel.copySelected()
                close()
                NSApp.hide(nil)
                #else
                if !HistoryPanelViewModel.isAccessibilityTrusted() {
                    _ = HistoryPanelViewModel.isAccessibilityTrusted(prompt: true)
                    return nil
                }
                try? viewModel.pasteSelected()
                close()
                NSApp.hide(nil)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    viewModel.simulatePaste()
                }
                #endif
                return nil
            }

            // Escape: dismiss AI state first, then close panel
            if keyCode == kVK_Escape {
                if viewModel.actionsVisible || viewModel.aiResult != nil || viewModel.aiError != nil {
                    viewModel.closeActions()
                    viewModel.clearAIOutput()
                } else {
                    close()
                }
                return nil
            }

            if keyCode == kVK_ANSI_D && modifiers.contains(.command) {
                try? viewModel.toggleFavoriteSelected()
                return nil
            }

            if keyCode == kVK_ANSI_P && modifiers.contains(.command),
               let item = viewModel.selectedItem,
               item.type == .image {
                pinImage(item)
                return nil
            }

            if keyCode == kVK_Delete && modifiers.contains(.command) {
                try? viewModel.deleteSelected()
                return nil
            }

            return event
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
    }

    private func icon(for item: ClipboardItem) -> String {
        switch item.type {
        case .text: return "T"
        case .image: return "I"
        case .file: return "F"
        }
    }

    private var actionMenuEntries: [ActionMenuEntry] {
        guard let item = viewModel.selectedItem else { return [] }
        switch item.type {
        case .text:
            let clipboardEntries = [
                ActionMenuEntry(id: "copy", title: "Copy", kind: .clipboard(.copy)),
                ActionMenuEntry(id: "paste", title: "Paste", kind: .clipboard(.paste)),
                ActionMenuEntry(id: "paste-plain", title: "Paste as Plain Text", kind: .clipboard(.pastePlainText)),
                ActionMenuEntry(id: "edit-copy", title: "Edit and Copy…", kind: .clipboard(.editAndCopy))
            ]
            let aiEntries = viewModel.aiActions.enumerated().map { index, action in
                ActionMenuEntry(id: "ai-\(action.id)", title: "AI · \(action.title)", kind: .ai(index))
            }
            return clipboardEntries + aiEntries
        case .image:
            return [
                ActionMenuEntry(id: "pin", title: "Pin on Top", kind: .clipboard(.pinImage)),
                ActionMenuEntry(id: "save-image", title: "Save Image As…", kind: .clipboard(.saveImage)),
                ActionMenuEntry(id: "ocr", title: "Recognize Text (OCR)", kind: .clipboard(.recognizeText)),
                ActionMenuEntry(id: "compress", title: "Compress as JPEG…", kind: .clipboard(.compressImage))
            ]
        case .file:
            return [
                ActionMenuEntry(id: "reveal", title: "Show in Finder", kind: .clipboard(.revealInFinder)),
                ActionMenuEntry(id: "copy-path", title: "Copy Path", kind: .clipboard(.copyFilePaths)),
                ActionMenuEntry(id: "copy-name", title: "Copy Filename", kind: .clipboard(.copyFileNames))
            ]
        }
    }

    private func moveActionSelection(delta: Int) {
        let maxIndex = max(actionMenuEntries.count - 1, 0)
        selectedActionIndex = min(max(selectedActionIndex + delta, 0), maxIndex)
    }

    private func runSelectedMenuAction() {
        guard let item = viewModel.selectedItem,
              actionMenuEntries.indices.contains(selectedActionIndex) else { return }
        switch actionMenuEntries[selectedActionIndex].kind {
        case .clipboard(let action):
            viewModel.closeActions()
            performContextAction(action, item)
        case .ai(let index):
            viewModel.selectedAIActionIndex = index
            Task { await viewModel.runSelectedAIAction() }
        }
    }
}
