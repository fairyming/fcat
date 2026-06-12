import Carbon
import AppKit
import SwiftUI

public struct HistoryPanelView: View {
    @ObservedObject private var viewModel: HistoryPanelViewModel
    @FocusState private var searchFocused: Bool
    @State private var keyMonitor: Any?
    private let close: () -> Void

    public init(viewModel: HistoryPanelViewModel, close: @escaping () -> Void) {
        self.viewModel = viewModel
        self.close = close
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Top bar: search + category
            VStack(spacing: 8) {
                TextField("Search clipboard history", text: $viewModel.query)
                    .textFieldStyle(.roundedBorder)
                    .focused($searchFocused)
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
                            Text(item.isFavorite ? "★" : "☆")
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
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            if selectedItem.type == .image, let assetPath = selectedItem.assetPath {
                                if let image = NSImage(contentsOfFile: assetPath) {
                                    Image(nsImage: image)
                                        .resizable()
                                        .aspectRatio(contentMode: .fit)
                                        .frame(maxHeight: .infinity)
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
                Text("Enter = copy  |  ↑↓ = select  |  ⌘D = favorite  |  Fn⌫ = delete  |  Esc = close")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                #else
                Text("Enter = paste  |  ↑↓ = select  |  ⌘D = favorite  |  Fn⌫ = delete  |  Esc = close")
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
    }

    private func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let keyCode = Int(event.keyCode)
            let modifiers = event.modifierFlags

            if keyCode == kVK_Return && modifiers.isDisjoint(with: [.command, .option, .control, .shift]) {
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

            if keyCode == kVK_UpArrow {
                viewModel.moveSelection(delta: -1)
                return nil
            }

            if keyCode == kVK_DownArrow {
                viewModel.moveSelection(delta: 1)
                return nil
            }

            if keyCode == kVK_Escape {
                close()
                return nil
            }

            if keyCode == kVK_ANSI_D && modifiers.contains(.command) {
                try? viewModel.toggleFavoriteSelected()
                return nil
            }

            if keyCode == kVK_ForwardDelete {
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
}