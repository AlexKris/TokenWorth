import SwiftUI
import TokenWorthCore

struct ProviderTabBar: View {
    let selectedTab: AppTab
    let onSelect: (AppTab) -> Void

    var body: some View {
        HStack(spacing: 4) {
            ForEach(AppTab.allTabs) { tab in
                let isSelected = tab == selectedTab
                Button {
                    withAnimation(.snappy(duration: 0.2)) {
                        onSelect(tab)
                    }
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: tab.sfSymbolName)
                            .font(.system(size: 13.5, weight: isSelected ? .semibold : .medium))
                            .foregroundStyle(iconColor(for: tab, isSelected: isSelected))
                        Text(tab.title)
                            .font(.system(size: 10, weight: isSelected ? .semibold : .medium))
                            .lineLimit(1)
                            .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .background {
                        if isSelected {
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(TokenWorthTheme.tabPillBackground)
                                .shadow(color: .black.opacity(0.08), radius: 3, y: 1)
                                .overlay {
                                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                                        .stroke(Color.white.opacity(0.6), lineWidth: 0.5)
                                }
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(TokenWorthTheme.tabTrackBackground)
                .overlay {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(TokenWorthTheme.subtleBorder, lineWidth: 0.75)
                }
        }
    }

    private func iconColor(for tab: AppTab, isSelected: Bool) -> Color {
        switch tab {
        case .overview:
            return isSelected ? TokenWorthTheme.activeBlue : .secondary
        case .provider(let provider):
            return isSelected ? TokenWorthTheme.brandColor(for: provider) : TokenWorthTheme.brandColor(for: provider).opacity(0.75)
        }
    }
}
