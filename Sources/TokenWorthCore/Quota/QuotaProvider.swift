import Foundation
import Security

public struct HTTPResponse: Sendable {
    public let statusCode: Int
    public let data: Data
    public let headers: [String: String]

    public init(statusCode: Int, data: Data, headers: [String: String] = [:]) {
        self.statusCode = statusCode
        self.data = data
        self.headers = headers
    }
}

public protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> HTTPResponse
}

public struct URLSessionTransport: HTTPTransport {
    private let session: URLSession

    public init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest = 15
            config.timeoutIntervalForResource = 20
            self.session = URLSession(configuration: config)
        }
    }

    public func send(_ request: URLRequest) async throws -> HTTPResponse {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw QuotaProviderError.invalidResponse
        }
        var headerMap: [String: String] = [:]
        for (k, v) in http.allHeaderFields {
            headerMap[String(describing: k).lowercased()] = String(describing: v)
        }
        return HTTPResponse(statusCode: http.statusCode, data: data, headers: headerMap)
    }
}

public enum QuotaProviderError: Error, LocalizedError, Sendable {
    case invalidResponse
    case unauthorized(String)
    case rateLimited(retryAfterSeconds: TimeInterval?)
    case httpStatus(Int, String)
    case decodingFailed(String)

    public var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid HTTP response"
        case .unauthorized(let msg):
            return "Unauthorized: \(msg)"
        case .rateLimited:
            return "Rate limited (HTTP 429)"
        case .httpStatus(let code, let detail):
            return detail.isEmpty ? "HTTP \(code)" : "HTTP \(code): \(detail)"
        case .decodingFailed(let detail):
            return "Failed to parse quota payload: \(detail)"
        }
    }
}

public protocol QuotaProvider: Sendable {
    var provider: ProviderID { get }
    func fetchQuota(for account: AccountProfile, settings: AppSettings) async -> AccountQuotaSnapshot
}

enum KeychainReader {
    static func readGenericPassword(service: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else { return nil }
        return result as? Data
    }
}

enum QuotaJSONHelpers {
    static func extractRetryAfter(from headers: [String: String]) -> TimeInterval? {
        guard let raw = headers["retry-after"], let seconds = Double(raw) else { return nil }
        return max(1, seconds)
    }

    static func readJSONDictionary(at path: String) -> [String: Any]? {
        let expanded = AppPaths.expandTilde(path)
        guard FileManager.default.fileExists(atPath: expanded),
              let data = try? Data(contentsOf: URL(fileURLWithPath: expanded)),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return obj
    }

    static func doubleValue(_ raw: Any?) -> Double? {
        if let d = raw as? Double { return d }
        if let i = raw as? Int { return Double(i) }
        if let n = raw as? NSNumber { return n.doubleValue }
        if let s = raw as? String, let d = Double(s) { return d }
        return nil
    }

    static func stringValue(_ raw: Any?) -> String? {
        if let s = raw as? String, !s.isEmpty { return s }
        return nil
    }

    static func parseDate(_ raw: Any?) -> Date? {
        LogParserHelpers.parseDate(raw)
    }
}

enum ExternalQuotaBridge {
    struct ExternalWindowPayload: Decodable {
        let id: String?
        let label: String
        let durationSeconds: TimeInterval?
        let usedPercent: Double
        let resetsAt: String?
        let resetsAtEpoch: Double?
    }

    struct ExternalGroupPayload: Decodable {
        let id: String?
        let title: String
        let windows: [ExternalWindowPayload]
    }

    struct ExternalAccountPayload: Decodable {
        let accountID: String?
        let email: String?
        let planName: String?
        let extraUsageUSD: Double?
        let extraUsageLimitUSD: Double?
        let groups: [ExternalGroupPayload]
    }

    struct ExternalMultiAccountEnvelope: Decodable {
        let accounts: [ExternalAccountPayload]
    }

    static func fetchIfConfigured(
        for account: AccountProfile,
        defaultFilePath: URL? = nil,
        fetchedAt: Date = Date()
    ) -> AccountQuotaSnapshot? {
        if let filePath = account.externalQuotaFilePath?.trimmingCharacters(in: .whitespacesAndNewlines),
           !filePath.isEmpty {
            let url = URL(fileURLWithPath: AppPaths.expandTilde(filePath))
            if let data = try? Data(contentsOf: url) {
                return decodePayload(data: data, account: account, fetchedAt: fetchedAt)
            }
            return AccountQuotaSnapshot(
                accountID: account.id,
                provider: account.provider,
                planName: account.planName,
                fetchedAt: fetchedAt,
                status: .error("Quota file not found: \(url.lastPathComponent)")
            )
        }

        if let defaultFilePath, FileManager.default.fileExists(atPath: defaultFilePath.path),
           let data = try? Data(contentsOf: defaultFilePath) {
            return decodePayload(data: data, account: account, fetchedAt: fetchedAt)
        }

        if let command = account.externalQuotaCommand?.trimmingCharacters(in: .whitespacesAndNewlines),
           !command.isEmpty {
            return runCommand(command, account: account, fetchedAt: fetchedAt)
        }

        return nil
    }

    static func decodePayload(data: Data, account: AccountProfile, fetchedAt: Date = Date()) -> AccountQuotaSnapshot {
        let decoder = JSONDecoder()

        if let multi = try? decoder.decode(ExternalMultiAccountEnvelope.self, from: data) {
            let matched = multi.accounts.first(where: {
                $0.accountID == account.id ||
                ($0.email != nil && $0.email == account.email)
            }) ?? multi.accounts.first
            if let matched {
                return mapPayload(matched, account: account, fetchedAt: fetchedAt)
            }
        }

        if let single = try? decoder.decode(ExternalAccountPayload.self, from: data) {
            return mapPayload(single, account: account, fetchedAt: fetchedAt)
        }

        return AccountQuotaSnapshot(
            accountID: account.id,
            provider: account.provider,
            planName: account.planName,
            fetchedAt: fetchedAt,
            status: .error("Invalid external quota JSON schema")
        )
    }

    private static func mapPayload(
        _ payload: ExternalAccountPayload,
        account: AccountProfile,
        fetchedAt: Date
    ) -> AccountQuotaSnapshot {
        let groups = payload.groups.enumerated().map { gIdx, grp in
            let windows = grp.windows.enumerated().map { wIdx, win in
                let resetDate: Date? = win.resetsAt.flatMap { LogParserHelpers.parseISO8601($0) }
                    ?? win.resetsAtEpoch.map { LogParserHelpers.dateFromEpoch($0) }
                let inferredDuration = win.durationSeconds ?? inferDuration(from: win.label)
                return QuotaWindow(
                    id: win.id ?? "\(grp.title)-\(win.label)-\(wIdx)",
                    label: win.label,
                    durationSeconds: inferredDuration,
                    usedPercent: win.usedPercent,
                    resetsAt: resetDate
                )
            }
            return QuotaGroup(id: grp.id ?? "group-\(gIdx)", title: grp.title, windows: windows)
        }

        return AccountQuotaSnapshot(
            accountID: account.id,
            provider: account.provider,
            planName: payload.planName ?? account.planName,
            groups: groups,
            extraUsageUSD: payload.extraUsageUSD,
            extraUsageLimitUSD: payload.extraUsageLimitUSD,
            fetchedAt: fetchedAt,
            status: .live
        )
    }

    private static func inferDuration(from label: String) -> TimeInterval {
        let lower = label.lowercased()
        if lower.contains("7d") || lower.contains("week") { return 7 * 24 * 3600 }
        if lower.contains("5h") || lower.contains("session") { return 5 * 3600 }
        if lower.contains("24h") || lower.contains("1d") { return 24 * 3600 }
        return 5 * 3600
    }

    private static func runCommand(
        _ command: String,
        account: AccountProfile,
        fetchedAt: Date
    ) -> AccountQuotaSnapshot {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", command]

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        do {
            try process.run()
            process.waitUntilExit()
            let data = stdout.fileHandleForReading.readDataToEndOfFile()
            guard process.terminationStatus == 0 else {
                let errData = stderr.fileHandleForReading.readDataToEndOfFile()
                let errMsg = String(data: errData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "Command failed"
                return AccountQuotaSnapshot(
                    accountID: account.id,
                    provider: account.provider,
                    planName: account.planName,
                    fetchedAt: fetchedAt,
                    status: .error(errMsg.isEmpty ? "Exit \(process.terminationStatus)" : errMsg)
                )
            }
            return decodePayload(data: data, account: account, fetchedAt: fetchedAt)
        } catch {
            return AccountQuotaSnapshot(
                accountID: account.id,
                provider: account.provider,
                planName: account.planName,
                fetchedAt: fetchedAt,
                status: .error(error.localizedDescription)
            )
        }
    }
}
