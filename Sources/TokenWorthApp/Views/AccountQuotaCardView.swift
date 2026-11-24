import SwiftUI
import TokenWorthCore

struct AccountQuotaCardView: View {
    let account: AccountProfile
    let snapshot: AccountQuotaSnapshot?
    let accountUsage: AccountUsageRow?
    let maskEmails: Bool
    let showSwitchAction: Bool
    let formatCurrency: (Double) -> String
    let onSwitchTap: () -> Void

    var body: some View {
        ZStack(alignment: .leading) {
            VStack(alignment: .leading, spacing: 11) {
                headerRow
                quotaContent
                footerUsageStrip
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background {
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .fill(account.isActive ? TokenWorthTheme.activeCardBackground : TokenWorthTheme.cardBackground)
                    .overlay {
                        RoundedRectangle(cornerRadius: 15, style: .continuous)
                            .stroke(
                                account.isActive ? TokenWorthTheme.activeBlue.opacity(0.45) : TokenWorthTheme.subtleBorder,
                                lineWidth: account.isActive ? 1.2 : 0.8
                            )
                    }
                    .shadow(
                        color: account.isActive ? TokenWorthTheme.activeBlue.opacity(0.12) : .black.opacity(0.04),
                        radius: account.isActive ? 7 : 3,
                        y: 1
                    )
            }

            if account.isActive {
                Capsule()
                    .fill(TokenWorthTheme.activeBlue)
                    .frame(width: 3.5, height: 34)
                    .offset(x: -1)
            }
        }
    }

    private var headerRow: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(account.maskedEmailDisplay(masked: maskEmails))
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                Text(snapshot?.planName ?? account.planName)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 3) {
                if account.isActive {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(TokenWorthTheme.activeBlue)
                            .frame(width: 5, height: 5)
                        Text("Active")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundStyle(TokenWorthTheme.activeBlue)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(TokenWorthTheme.activeBlueSoft, in: Capsule())

                    if let fetchedAt = snapshot?.fetchedAt {
                        Text(TokenWorthFormatter.formatRelativeTime(since: fetchedAt))
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                    }
                } else if showSwitchAction {
                    Button(action: onSwitchTap) {
                        Label("Switch", systemImage: "arrow.left.arrow.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(TokenWorthTheme.activeBlue)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4)
                            .background(
                                Capsule()
                                    .fill(TokenWorthTheme.activeBlueSoft.opacity(0.7))
                                    .overlay(Capsule().stroke(TokenWorthTheme.activeBlue.opacity(0.35), lineWidth: 0.7))
                            )
                    }
                    .buttonStyle(.plain)
                    .help("Phase 1 is read-only; Phase 2 adds isolated profile switching")
                }
            }
        }
    }

    @ViewBuilder
    private var quotaContent: some View {
        if let snapshot, !snapshot.groups.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(snapshot.groups) { group in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(group.title)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.primary.opacity(0.85))

                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(group.windows) { window in
                                QuotaProgressRow(window: window, now: Date())
                            }
                        }
                    }
                }

                if let extraUsed = snapshot.extraUsageUSD {
                    HStack {
                        Text("Extra usage")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        Spacer()
                        if let limit = snapshot.extraUsageLimitUSD {
                            Text("\(formatCurrency(extraUsed)) / \(formatCurrency(limit))")
                                .font(.system(size: 11, weight: .medium, design: .rounded))
                                .monospacedDigit()
                        } else {
                            Text(formatCurrency(extraUsed))
                                .font(.system(size: 11, weight: .medium, design: .rounded))
                                .monospacedDigit()
                        }
                    }
                    .padding(.top, 2)
                }
            }
        } else if let msg = snapshot?.status.statusMessage {
            HStack(spacing: 6) {
                Image(systemName: "info.circle")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                Text(msg)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(TokenWorthTheme.progressTrack.opacity(0.55), in: RoundedRectangle(cornerRadius: 8))
        } else {
            Text("Waiting for initial quota fetch…")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }

    private var footerUsageStrip: some View {
        VStack(spacing: 6) {
            Divider().opacity(0.5)
            HStack(spacing: 12) {
                HStack(spacing: 4) {
                    Text("Tokens")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                    Text(TokenWorthFormatter.formatTokens(accountUsage?.tokens.total ?? 0))
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                }

                Spacer()

                HStack(spacing: 4) {
                    Text("API Equiv")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                    Text(formatCurrency(accountUsage?.cost.totalUSD ?? 0))
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(TokenWorthTheme.brandColor(for: account.provider))
                }
            }
        }
    }
}
