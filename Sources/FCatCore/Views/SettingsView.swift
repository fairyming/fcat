import Carbon
import SwiftUI

public struct SettingsView: View {
    @ObservedObject private var viewModel: SettingsViewModel
    private let saveHotKey: (HotKey) -> Void

    public init(viewModel: SettingsViewModel, saveHotKey: @escaping (HotKey) -> Void) {
        self.viewModel = viewModel
        self.saveHotKey = saveHotKey
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Set a global shortcut")
                .font(.title2.bold())
            Text("Choose the shortcut used to show and hide clipboard history.")
                .foregroundStyle(.secondary)

            Button("Use Command + Option + Space") {
                let hotKey = HotKey(keyCode: 49, modifiers: UInt32(cmdKey | optionKey))
                viewModel.save(hotKey: hotKey)
                saveHotKey(hotKey)
            }
            .keyboardShortcut(.space, modifiers: [.command, .option])

            if viewModel.hasHotKey {
                Text("Shortcut saved")
                    .foregroundStyle(.green)
            }
        }
        .padding(24)
        .frame(width: 420, height: 220)
    }
}
