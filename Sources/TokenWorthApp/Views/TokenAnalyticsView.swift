import SwiftUI
import Charts
import TokenWorthCore

struct TokenAnalyticsView: View {
    let summary: UsageSummary
    @Binding var selectedRange: TimeRange
    let formatCurrency: (Double) -> String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Tokens & API Cost")
                    .font(.system(size: 12.5, weight: .semibold))
                Spacer()
                Picker("Range", selection: $selectedRange) {
                    ForEach(TimeRange.allCases) { range in
                        Text(range.displayTitle).tag(range)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 190)
            }

            kpiGrid

            if !summary.dailySeries.isEmpty {
                dailyChartCard
            }

            if !summary.byModel.isEmpty {
                modelBreakdownCard
            } else {
                emptyUsageCard
            }
        }
    }

    private var kpiGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
            kpiCard(
                title: "API Equivalent",
                value: formatCurrency(summary.totalCost.totalUSD),
                subtitle: summary.totalCost.isEstimatedOrUnpriced ? "Some unpriced models" : "\(summary.eventCount) turns",
                accent: TokenWorthTheme.activeBlue
            )

            kpiCard(
                title: "Total Tokens",
                value: TokenWorthFormatter.formatTokens(summary.totalTokens.total),
                subtitle: "In \(TokenWorthFormatter.formatTokens(summary.totalTokens.input)) · Out \(TokenWorthFormatter.formatTokens(summary.totalTokens.output))",
                accent: .primary
            )

            kpiCard(
                title: "Cache Savings",
                value: formatCurrency(summary.totalCost.cacheSavingsUSD),
                subtitle: "\(Int((summary.totalTokens.cacheHitRate * 100).rounded()))% hit · Think \(TokenWorthFormatter.formatTokens(summary.totalTokens.reasoning))",
                accent: Color(red: 0.20, green: 0.65, blue: 0.34)
            )

            kpiCard(
                title: "Subscription ROI",
                value: summary.roiMultiple.map { String(format: "%.2fx", $0) } ?? "—",
                subtitle: summary.totalMonthlySubscriptionUSD > 0
                    ? "vs \(formatCurrency(summary.totalMonthlySubscriptionUSD))/mo"
                    : "No subscription fee set",
                accent: Color(red: 0.82, green: 0.48, blue: 0.14)
            )
        }
    }

    private func kpiCard(title: String, value: String, subtitle: String, accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(accent)
            Text(subtitle)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(TokenWorthTheme.cardBackground)
                .overlay {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .stroke(TokenWorthTheme.subtleBorder, lineWidth: 0.75)
                }
        }
    }

    private var dailyChartCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Daily API Cost")
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(.secondary)

            Chart {
                ForEach(summary.dailySeries) { day in
                    ForEach(day.providerBreakdown) { slice in
                        BarMark(
                            x: .value("Day", day.date, unit: .day),
                            y: .value("Cost", slice.costUSD)
                        )
                        .foregroundStyle(TokenWorthTheme.brandColor(for: slice.provider))
                        .cornerRadius(2)
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 5)) { value in
                    AxisValueLabel(format: .dateTime.month(.abbreviated).day(), centered: true)
                        .font(.system(size: 9.5))
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.4, dash: [2, 2]))
                    AxisValueLabel {
                        if let usd = value.as(Double.self) {
                            Text(formatCurrency(usd))
                                .font(.system(size: 9.5))
                        }
                    }
                }
            }
            .frame(height: 110)
        }
        .padding(10)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(TokenWorthTheme.cardBackground)
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(TokenWorthTheme.subtleBorder, lineWidth: 0.75)
                }
        }
    }

    private var modelBreakdownCard: some View {
        let maxCost = max(summary.byModel.map(\.cost.totalUSD).max() ?? 0, 0.0001)
        return VStack(alignment: .leading, spacing: 7) {
            Text("Model Breakdown")
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(.secondary)

            VStack(spacing: 7) {
                ForEach(summary.byModel.prefix(8)) { row in
                    let ratio = min(max(row.cost.totalUSD / maxCost, 0.03), 1.0)
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(TokenWorthTheme.brandColor(for: row.provider))
                                .frame(width: 6, height: 6)
                            Text(row.model)
                                .font(.system(size: 11, weight: .medium))
                                .lineLimit(1)
                            Spacer()
                            Text(TokenWorthFormatter.formatTokens(row.tokens.total))
                                .font(.system(size: 10.5, design: .rounded))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                            Text(formatCurrency(row.cost.totalUSD))
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .monospacedDigit()
                                .frame(width: 58, alignment: .trailing)
                        }

                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(TokenWorthTheme.progressTrack)
                                Capsule()
                                    .fill(TokenWorthTheme.brandColor(for: row.provider).opacity(0.85))
                                    .frame(width: geo.size.width * ratio)
                            }
                        }
                        .frame(height: 4)
                    }
                }
            }
        }
        .padding(10)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(TokenWorthTheme.cardBackground)
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(TokenWorthTheme.subtleBorder, lineWidth: 0.75)
                }
        }
    }

    private var emptyUsageCard: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("No local token logs found in this range")
                .font(.system(size: 11.5, weight: .semibold))
            Text("TokenWorth scans ~/.claude/projects, ~/.codex/sessions, ~/.grok, and ~/.gemini/tmp read-only. You can also turn on Demo Mode in Settings to preview.")
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(TokenWorthTheme.cardBackground)
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(TokenWorthTheme.subtleBorder, lineWidth: 0.75)
                }
        }
    }
}
