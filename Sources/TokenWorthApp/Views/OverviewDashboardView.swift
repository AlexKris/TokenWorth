import SwiftUI
import TokenWorthCore

struct OverviewDashboardView: View {
    @Bindable var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            providerStatusGrid

            TokenAnalyticsView(
                summary: state.usageSummary,
                selectedRange: $state.selectedTimeRange,
                formatCurrency: state.formatCurrency
            )
        }
    }

    private var providerStatusGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
            ForEach(ProviderID.allCases) { provider in
                let accounts = state.accounts(for: provider)
                let primaryAccount = accounts.first(where: \.isActive) ?? accounts.first
                let snapshot = primaryAccount.flatMap { state.quotaSnapshots[$0.id] }
                let provUsage = state.providerUsage(for: provider)

                Button {
                    withAnimation(.snappy(duration: 0.2)) {
                        state.selectTab(.provider(provider))
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 6) {
                            Image(systemName: provider.sfSymbolName)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(TokenWorthTheme.brandColor(for: provider))
                            Text(provider.displayName)
                                .font(.system(size: 12, weight: .semibold))
                            Spacer()
                            if let snapshot, snapshot.status.isHealthy, let maxPct = snapshot.groups.flatMap(\.windows).map(\.usedPercent).max() {
                                Text(TokenWorthFormatter.formatPercent(maxPct))
                                    .font(.system(size: 11, weight: .bold, design: .rounded))
                                    .monospacedDigit()
                                    .foregroundStyle(TokenWorthTheme.quotaColor(for: maxPct))
                            } else {
                                Text("—")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                        }

                        if let snapshot, let firstWindow = snapshot.groups.first?.windows.first {
                            GeometryReader { geo in
                                let ratio = min(max(firstWindow.usedPercent / 100.0, 0), 1)
                                ZStack(alignment: .leading) {
                                    Capsule().fill(TokenWorthTheme.progressTrack)
                                    if firstWindow.usedPercent > 0 {
                                        Capsule()
                                            .fill(TokenWorthTheme.quotaColor(for: firstWindow.usedPercent))
                                            .frame(width: max(6, geo.size.width * ratio))
                                    }
                                }
                            }
                            .frame(height: 5)
                        } else {
                            Capsule()
                                .fill(TokenWorthTheme.progressTrack)
                                .frame(height: 5)
                        }

                        HStack {
                            Text(TokenWorthFormatter.formatTokens(provUsage?.tokens.total ?? 0))
                                .font(.system(size: 10, design: .rounded))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                            Spacer()
                            Text(state.formatCurrency(provUsage?.cost.totalUSD ?? 0))
                                .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                                .monospacedDigit()
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 9)
                    .background {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(TokenWorthTheme.cardBackground)
                            .overlay {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(TokenWorthTheme.subtleBorder, lineWidth: 0.75)
                            }
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }
}
