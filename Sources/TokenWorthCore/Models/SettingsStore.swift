import Foundation

public struct SettingsStore: Sendable {
    public let fileURL: URL

    public init(fileURL: URL = AppPaths.settingsFile) {
        self.fileURL = fileURL
    }

    public func load() -> AppSettings {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return AppSettings()
        }
        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            return try decoder.decode(AppSettings.self, from: data)
        } catch {
            return AppSettings()
        }
    }

    public func save(_ settings: AppSettings) throws {
        let dir = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(settings)
        try data.write(to: fileURL, options: .atomic)
    }
}

public enum AppPaths {
    public static var homeDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
    }

    public static var applicationSupportDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? homeDirectory.appendingPathComponent("Library/Application Support", isDirectory: true)
        return base.appendingPathComponent("TokenWorth", isDirectory: true)
    }

    public static var settingsFile: URL {
        applicationSupportDirectory.appendingPathComponent("settings.json")
    }

    public static var pricingOverridesFile: URL {
        applicationSupportDirectory.appendingPathComponent("pricing-overrides.json")
    }

    public static var importsDirectory: URL {
        applicationSupportDirectory.appendingPathComponent("imports", isDirectory: true)
    }

    public static var antigravityQuotaFile: URL {
        applicationSupportDirectory.appendingPathComponent("antigravity-quota.json")
    }

    public static func expandTilde(_ path: String) -> String {
        NSString(string: path).expandingTildeInPath
    }
}
