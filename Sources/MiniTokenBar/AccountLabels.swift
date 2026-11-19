import Foundation

// Manual, user-edited labels for services that don't locally expose which
// account/org you're signed into (Claude Desktop only caches a bare org UUID).
// Edit ~/Library/Application Support/MiniTokenBar/labels.json, e.g. {"claude": "Corporate"}.
enum AccountLabels {
    private static var fileURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/MiniTokenBar/labels.json")
    }
    private static var values: [String: Any] {
        guard let data = try? Data(contentsOf: fileURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        return json
    }
    static var claude: String? { (values["claude"] as? String).flatMap { $0.isEmpty ? nil : $0 } }
}
