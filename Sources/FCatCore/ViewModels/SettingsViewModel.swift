import Combine
import Foundation

public final class SettingsViewModel: ObservableObject {
    @Published public var hotKey: HotKey?
    private let defaults: UserDefaults
    private let key = "FCat.hotKey"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.hotKey = Self.load(defaults: defaults, key: key)
    }

    public var hasHotKey: Bool { hotKey != nil }

    public func save(hotKey: HotKey?) {
        self.hotKey = hotKey
        if let hotKey {
            let data = try? JSONEncoder().encode(hotKey)
            defaults.set(data, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }

    private static func load(defaults: UserDefaults, key: String) -> HotKey? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(HotKey.self, from: data)
    }
}
