import SwiftUI
import TokenWorthCore

struct PopoverRootView: View {
    @Bindable var state: AppState

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                ProviderTabBar(selectedTab: state.selectedTab) { tab in
                    state.selectTab(tab)
                }
                .padding(.horizontal, 12)
                .padding(.top, 12)
                .padding(.bottom, 10)

                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        if state.selectedTab == .overview {
                            OverviewDashboardView(state: state)
                        } else if case .provider(let provider) = state.selectedTab {
                            providerContent(for: provider)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 10)
                }
                .frame(maxHeight: TokenWorthTheme.popoverBodyMaxHeight)

                if let toast = state.statusToast {
                    HStack(spacing: 6) {
                        Image(systemName: "info.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(TokenWorthTheme.activeBlue)
                        Text(toast)
                            .font(.system(size: 11))
                            .lineLimit(2)
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(TokenWorthTheme.activeBlueSoft.opacity(0.85))
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                Divider().opacity(0.6)
                footerBar
            }
            .background(TokenWorthTheme.shellBackground)

            if let modal = state.activeModal {
                modalOverlay(for: modal)
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }
        }
        .frame(width: TokenWorthTheme.popoverWidth)
        .animation(.easeInOut(duration: 0.16), value: state.activeModal)
        .animation(.easeInOut(duration: 0.2), value: state.statusToast)
    }

    @ViewBuilder
    private func providerContent(for provider: ProviderID) -> some View {
        let accounts = state.accounts(for: provider)
        let hasMultiple = accounts.count > 1

        if accounts.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("No \(provider.displayName) accounts configured")
                    .font(.system(size: 12.5, weight: .semibold))
                Button("Add \(provider.displayName) Account") {
                    state.openAddAccount()
                }
                .controlSize(.small)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(TokenWorthTheme.cardBackground, in: RoundedRectangle(cornerRadius: 14))
        } else {
            VStack(spacing: 10) {
                ForEach(accounts) { account in
                    AccountQuotaCardView(
                        account: account,
                        snapshot: state.quotaSnapshots[account.id],
                        accountUsage: state.accountUsage(for: account.id),
                        maskEmails: state.settings.maskEmails,
                        showSwitchAction: hasMultiple || !account.isActive,
                        formatCurrency: state.formatCurrency,
                        onSwitchTap: {
                            state.notifySwitchPreview(account: account)
                        }
                    )
                }
            }
        }

        TokenAnalyticsView(
            summary: state.usageSummary,
            selectedRange: $state.selectedTimeRange,
            formatCurrency: state.formatCurrency
        )
    }

    private var footerBar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "gauge.with.dots.needle.33percent")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text("TokenWorth")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary.opacity(0.85))

                if state.settings.useDemoData {
                    Text("Demo")
                        .font(.system(size: 9.5, weight: .bold))
                        .foregroundStyle(TokenWorthTheme.activeBlue)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(TokenWorthTheme.activeBlueSoft, in: Capsule())
                }
            }

            Spacer()

            if let updated = state.lastRefreshDate {
                Text(TokenWorthFormatter.formatRelativeTime(since: updated))
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            }

            Button {
                Task { await state.refreshAll(force: true) }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12.5, weight: .medium))
                    .rotationEffect(.degrees(state.isRefreshing ? 360 : 0))
                    .animation(
                        state.isRefreshing
                            ? .linear(duration: 0.9).repeatForever(autoreverses: false)
                            : .default,
                        value: state.isRefreshing
                    )
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Refresh quotas and local logs")

            Button {
                state.openAddAccount()
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 13.5, weight: .medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Add account")

            Button {
                state.openSettings()
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 13, weight: .medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Settings")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func modalOverlay(for modal: ActiveModal) -> some View {
        Group {
            switch modal {
            case .settings:
                SettingsSheetView(state: state, draft: state.settingsDraft)
            case .addAccount:
                AddAccountSheetView(state: state, draft: state.addAccountDraft)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(TokenWorthTheme.shellBackground)
    }
}
