import Foundation

public protocol UsageLogParser: Sendable {
    var provider: ProviderID { get }
    func discoverFiles(for account: AccountProfile) -> [URL]
    func parseFile(at url: URL, accountID: String) throws -> [UsageEvent]
}

enum LogParserHelpers {
    static func discoverFiles(under directory: URL, matching predicate: (URL) -> Bool) -> [URL] {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: directory.path, isDirectory: &isDir), isDir.boolValue else {
            return []
        }

        guard let enumerator = fm.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var results: [URL] = []
        for case let fileURL as URL in enumerator {
            if predicate(fileURL) {
                results.append(fileURL)
            }
        }
        return results.sorted { $0.path < $1.path }
    }

    static func parseDate(_ raw: Any?) -> Date? {
        if let string = raw as? String {
            return parseISO8601(string)
        }
        if let num = raw as? Double {
            return dateFromEpoch(num)
        }
        if let num = raw as? Int {
            return dateFromEpoch(Double(num))
        }
        return nil
    }

    static func parseISO8601(_ string: String) -> Date? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: trimmed) {
            return date
        }

        let standard = ISO8601DateFormatter()
        standard.formatOptions = [.withInternetDateTime]
        if let date = standard.date(from: trimmed) {
            return date
        }

        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone(secondsFromGMT: 0)
        for fmt in ["yyyy-MM-dd'T'HH:mm:ss.SSSSSSXXXXX", "yyyy-MM-dd'T'HH:mm:ssXXXXX", "yyyy-MM-dd HH:mm:ss"] {
            df.dateFormat = fmt
            if let date = df.date(from: trimmed) {
                return date
            }
        }
        return nil
    }

    static func dateFromEpoch(_ raw: Double) -> Date {
        if raw > 10_000_000_000 {
            return Date(timeIntervalSince1970: raw / 1000.0)
        }
        return Date(timeIntervalSince1970: raw)
    }

    static func intValue(_ raw: Any?) -> Int? {
        if let i = raw as? Int { return i }
        if let d = raw as? Double { return Int(d) }
        if let n = raw as? NSNumber { return n.intValue }
        if let s = raw as? String, let i = Int(s) { return i }
        return nil
    }

    static func stringValue(_ raw: Any?) -> String? {
        if let s = raw as? String, !s.isEmpty { return s }
        return nil
    }

    static func streamJSONObjects(at url: URL, handler: (Int, [String: Any]) -> Void) throws {
        let data = try Data(contentsOf: url)
        guard !data.isEmpty else { return }
        var lineIndex = 0
        var start = data.startIndex
        let newlineByte: UInt8 = 0x0A

        while start < data.endIndex {
            let end = data[start...].firstIndex(of: newlineByte) ?? data.endIndex
            let lineData = data[start..<end]
            start = end < data.endIndex ? data.index(after: end) : data.endIndex

            if !lineData.isEmpty,
               let obj = try? JSONSerialization.jsonObject(with: Data(lineData)) as? [String: Any] {
                handler(lineIndex, obj)
            }
            lineIndex += 1
        }
    }
}
