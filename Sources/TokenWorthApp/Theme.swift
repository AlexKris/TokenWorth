import SwiftUI
import AppKit
import TokenWorthCore

enum TokenWorthTheme {
    static let popoverWidth: CGFloat = 416
    static let popoverBodyMaxHeight: CGFloat = 530

    static let activeBlue = Color(red: 0.23, green: 0.46, blue: 1.0)
    static let activeBlueSoft = Color(red: 0.90, green: 0.94, blue: 1.0)

    static let shellBackground = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(calibratedWhite: 0.13, alpha: 1.0)
            : NSColor(calibratedRed: 0.945, green: 0.945, blue: 0.935, alpha: 1.0)
    })

    static let cardBackground = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(calibratedWhite: 0.18, alpha: 0.95)
            : NSColor(calibratedRed: 0.975, green: 0.978, blue: 0.985, alpha: 0.96)
    })

    static let activeCardBackground = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(calibratedRed: 0.15, green: 0.20, blue: 0.30, alpha: 0.96)
            : NSColor(calibratedRed: 0.94, green: 0.962, blue: 1.0, alpha: 0.98)
    })

    static let tabTrackBackground = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(calibratedWhite: 0.20, alpha: 0.85)
            : NSColor(calibratedWhite: 0.88, alpha: 0.72)
    })

    static let tabPillBackground = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(calibratedWhite: 0.29, alpha: 1.0)
            : NSColor(calibratedRed: 0.96, green: 0.975, blue: 1.0, alpha: 1.0)
    })

    static let subtleBorder = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(calibratedWhite: 1.0, alpha: 0.10)
            : NSColor(calibratedWhite: 0.0, alpha: 0.09)
    })

    static let progressTrack = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(calibratedWhite: 1.0, alpha: 0.12)
            : NSColor(calibratedWhite: 0.0, alpha: 0.10)
    })

    static func brandColor(for provider: ProviderID) -> Color {
        switch provider {
        case .claude:
            return Color(red: 0.85, green: 0.47, blue: 0.34)
        case .codex:
            return Color(red: 0.24, green: 0.68, blue: 0.44)
        case .grok:
            return Color(red: 0.42, green: 0.45, blue: 0.88)
        case .antigravity:
            return activeBlue
        }
    }

    static func quotaColor(for usedPercent: Double) -> Color {
        if usedPercent >= 90 {
            return Color(red: 0.86, green: 0.24, blue: 0.24)
        } else if usedPercent >= 70 {
            return Color(red: 0.88, green: 0.56, blue: 0.12)
        } else {
            return Color(red: 0.26, green: 0.65, blue: 0.29)
        }
    }
}
