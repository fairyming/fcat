import Foundation

public enum JSONFormatter {
    public static func format(_ text: String) throws -> String {
        let data = Data(text.utf8)
        let object = try JSONSerialization.jsonObject(with: data)
        let formatted = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        guard let output = String(data: formatted, encoding: .utf8) else {
            throw NSError(domain: "FCat.JSONFormatter", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unable to encode formatted JSON"])
        }
        return output
    }
}
