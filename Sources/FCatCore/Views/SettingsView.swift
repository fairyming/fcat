import SwiftUI

public enum SettingsTab: String, CaseIterable, Identifiable {
    case shortcut
    case ai
    public var id: String { rawValue }
    public var displayName: String {
        switch self {
        case .shortcut: return "Shortcut"
        case .ai: return "AI Actions"
        }
    }
}

public struct SettingsView: View {
    @ObservedObject private var viewModel: SettingsViewModel
    @State private var selectedTab: SettingsTab = .shortcut
    private let saveHotKey: (HotKey) -> Void
    private let saveHistoryCountLimit: (Int) -> Void

    public init(viewModel: SettingsViewModel, saveHotKey: @escaping (HotKey) -> Void, saveHistoryCountLimit: @escaping (Int) -> Void = { _ in }) {
        self.viewModel = viewModel
        self.saveHotKey = saveHotKey
        self.saveHistoryCountLimit = saveHistoryCountLimit
    }

    public var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $selectedTab) {
                ForEach(SettingsTab.allCases) { tab in
                    Text(tab.displayName).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 24)
            .padding(.top, 16)
            .padding(.bottom, 8)

            Divider()

            switch selectedTab {
            case .shortcut:
                ShortcutSettingsView(viewModel: viewModel, saveHotKey: saveHotKey, saveHistoryCountLimit: saveHistoryCountLimit)
            case .ai:
                AISettingsView(viewModel: viewModel)
            }
        }
        .frame(width: 520, height: 460)
    }
}
