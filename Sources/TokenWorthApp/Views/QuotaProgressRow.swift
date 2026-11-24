import SwiftUI
import TokenWorthCore

private struct DownTriangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

struct QuotaProgressRow: View {
    let window: QuotaWindow
    var now: Date = Date()

    var body: some View {
        let color = TokenWorthTheme.quotaColor(for: window.usedPercent)
        let pace = window.pacePercent(at: now)

        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .bottom, spacing: 8) {
                Text(window.label)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 44, alignment: .leading)
                    .padding(.bottom, 1)

                GeometryReader { geo in
                    let trackWidth = max(1, geo.size.width)
                    let clampedRatio = min(max(window.usedPercent / 100.0, 0), 1)
                    let fillWidth: CGFloat = window.usedPercent <= 0
                        ? 0
                        : max(7, trackWidth * clampedRatio)

                    VStack(alignment: .leading, spacing: 2) {
                        ZStack(alignment: .leading) {
                            Color.clear.frame(height: 5)
                            if let pace {
                                let paceX = max(3, min(trackWidth - 3, trackWidth * (pace / 100.0)))
                                DownTriangle()
                                    .fill(Color.secondary.opacity(0.65))
                                    .frame(width: 6, height: 4.5)
                                    .offset(x: paceX - 3)
                            }
                        }

                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(TokenWorthTheme.progressTrack)
                                .frame(height: 7)

                            if fillWidth > 0 {
                                Capsule()
                                    .fill(color)
                                    .frame(width: fillWidth, height: 7)
                            }
                        }
                    }
                }
                .frame(height: 15)

                Text(TokenWorthFormatter.formatPercent(window.usedPercent))
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(color)
                    .frame(width: 36, alignment: .trailing)
            }

            Text(window.resetSummary(at: now))
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
                .padding(.leading, 52)
        }
    }
}
