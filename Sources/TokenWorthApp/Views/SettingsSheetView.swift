import SwiftUI
import AppKit
import TokenWorthCore

struct SettingsSheetView: View {
    @Bindable var state: AppState
    @Bindable var draft: SettingsDraftModel

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Settings")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Button("Cancel") {
                    state.activeModal = nil
                }
                .buttonStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

                Button("Save") {
                    state.updateSettings(draft.buildSettings())
                    state.activeModal = nil
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    sectionCard("General & Privacy") {
                        Toggle("Demo Mode (Sample Quotas & Tokens)", isOn: $draft.settings.useDemoData)
                        Toggle("Mask Account Emails (x•••••@g••••••)", isOn: $draft.settings.maskEmails)
                        Toggle("Allow macOS Keychain Reads (Claude opt-in)", isOn: $draft.settings.allowKeychainReads)
                            .help("Off by default to prevent macOS Keychain prompts on startup.")
                    }

                    sectionCard("Display & Polling") {
                        HStack {
                            Text("Currency")
                            Spacer()
                            Picker("", selection: $draft.settings.currency) {
                                ForEach(CurrencyDisplay.allCases) { curr in
                                    Text(curr.rawValue).tag(curr)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 90)
                        }

                        if draft.settings.currency == .cny {
                            HStack {
                                Text("USD → CNY Rate")
                                Spacer()
                                TextField("7.25", text: $draft.cnyRateText)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 80)
                                    .multilineTextAlignment(.trailing)
                            }
                        }

                        HStack {
                            Text("Menu Bar Badge")
                            Spacer()
                            Picker("", selection: $draft.settings.menuBarMode) {
                                ForEach(MenuBarDisplayMode.allCases) { mode in
                                    Text(mode.rawValue).tag(mode)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 140)
                        }

                        HStack {
                            Text("Refresh Interval")
                            Spacer()
                            Picker("", selection: $draft.settings.refreshIntervalSeconds) {
                                Text("60s").tag(60)
                                Text("3m").tag(180)
                                Text("5m").tag(300)
                                Text("10m").tag(600)
                            }
                            .labelsHidden()
                            .frame(width: 90)
                        }
                    }

                    sectionCard("Antigravity & Local Bridges") {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Antigravity quotas can be fed via a local JSON file (`antigravity-quota.json`) or external CLI command without touching IDE internals.")
                                .font(.system(size: 10.5))
                                .foregroundStyle(.secondary)

                            HStack(spacing: 8) {
                                Button("Create Quota JSON Template") {
                                    state.writeAntigravityQuotaTemplate()
                                }
                                .controlSize(.small)

                                Button("Open Data Folder") {
                                    state.openAppSupportFolder()
                                }
                                .controlSize(.small)
                            }
                        }
                    }

                    sectionCard("Configured Accounts (\(draft.settings.accounts.count))") {
                        VStack(spacing: 8) {
                            ForEach($draft.settings.accounts) { $account in
                                HStack(spacing: 8) {
                                    Circle()
                                        .fill(TokenWorthTheme.brandColor(for: account.provider))
                                        .frame(width: 7, height: 7)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text("\(account.provider.displayName) · \(account.displayName)")
                                            .font(.system(size: 11.5, weight: .medium))
                                        Text(account.planName)
                                            .font(.system(size: 10))
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Toggle("Active", isOn: $account.isActive)
                                        .labelsHidden()
                                        .toggleStyle(.switch)
                                        .controlSize(.mini)

                                    if draft.settings.accounts.count > 1 {
                                        Button {
                                            draft.settings.accounts.removeAll { $0.id == account.id }
                                        } label: {
                                            Image(systemName: "trash")
                                                .font(.system(size: 11))
                                                .foregroundStyle(.red.opacity(0.8))
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                    }

                    HStack {
                        Spacer()
                        Button("Quit TokenWorth") {
                            NSApplication.shared.terminate(nil)
                        }
                        .font(.system(size: 11.5))
                        .foregroundStyle(.red)
                    }
                    .padding(.top, 4)
                }
                .padding(14)
            }
        }
        .font(.system(size: 11.5))
    }

    private func sectionCard<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 8) {
                content()
            }
            .padding(10)
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
    }
}
