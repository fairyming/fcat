import AppKit
import Carbon
import SwiftUI

private final class HotKeyRecorderMonitor: ObservableObject {
    @Published var isRecording = false
    private var monitor: Any?
    private var viewModel: SettingsViewModel?
    private var saveHotKey: ((HotKey) -> Void)?

    func start(viewModel: SettingsViewModel, saveHotKey: @escaping (HotKey) -> Void) {
        self.viewModel = viewModel
        self.saveHotKey = saveHotKey
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.isRecording else { return event }
            let modifiers = UInt32(event.modifierFlags.rawValue)
            let keyCode = UInt32(event.keyCode)

            // Escape cancels recording
            if keyCode == UInt32(kVK_Escape) {
                self.stop()
                return nil
            }

            let hotKey = HotKey(keyCode: keyCode, modifiers: modifiers)
            viewModel.save(hotKey: hotKey)
            saveHotKey(hotKey)
            self.stop()
            return nil // consume the event
        }
    }

    func stop() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
        isRecording = false
    }
}

public struct ShortcutSettingsView: View {
    @ObservedObject private var viewModel: SettingsViewModel
    @StateObject private var recorder = HotKeyRecorderMonitor()
    private let saveHotKey: (HotKey) -> Void

    public init(viewModel: SettingsViewModel, saveHotKey: @escaping (HotKey) -> Void) {
        self.viewModel = viewModel
        self.saveHotKey = saveHotKey
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Global Shortcut")
                .font(.title2.bold())
            Text("Press any key combination to set the shortcut for showing and hiding clipboard history.")
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                Button(recorder.isRecording ? "Press shortcut now..." : "Record Shortcut") {
                    recorder.start(viewModel: viewModel, saveHotKey: saveHotKey)
                }
                .controlSize(.large)

                if let hotKey = viewModel.hotKey {
                    Text(hotKey.displayString)
                        .font(.title3.monospaced().bold())
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Color.accentColor.opacity(0.15)))
                }

                if viewModel.hasHotKey {
                    Button("Clear") {
                        viewModel.save(hotKey: nil)
                        saveHotKey(HotKey(keyCode: 0, modifiers: 0))
                    }
                    .controlSize(.small)
                }
            }

            if viewModel.hasHotKey && !recorder.isRecording {
                Text("Shortcut saved. Open Settings from the menu bar to change it later.")
                    .foregroundStyle(.green)
                    .font(.caption)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onDisappear { recorder.stop() }
    }
}

public struct AISettingsView: View {
    @ObservedObject private var viewModel: SettingsViewModel

    public init(viewModel: SettingsViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("AI Actions")
                .font(.title2.bold())

            Picker("Provider", selection: $viewModel.aiProvider) {
                ForEach(AIProvider.allCases) { provider in
                    Text(provider.displayName).tag(provider)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: viewModel.aiProvider) { newValue in
                viewModel.selectAIProvider(newValue)
            }

            TextField("API Base URL", text: $viewModel.aiBaseURL)
                .textFieldStyle(.roundedBorder)

            SecureField("API Key", text: $viewModel.aiAPIKey)
                .textFieldStyle(.roundedBorder)

            TextField("Model", text: $viewModel.aiModel)
                .textFieldStyle(.roundedBorder)

            HStack {
                TextField("Default Language", text: $viewModel.aiDefaultLanguage)
                    .textFieldStyle(.roundedBorder)
                TextField("Timeout", value: $viewModel.aiTimeoutSeconds, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 100)
                TextField("Max Tokens", value: $viewModel.aiMaxTokens, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 100)
            }

            HStack {
                Button("Save AI Settings") { viewModel.saveAISettings() }
                if let message = viewModel.aiSettingsMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(message.contains("Failed") ? .red : .green)
                }
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
