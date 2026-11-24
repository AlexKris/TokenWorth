import SwiftUI
import TokenWorthCore

struct AddAccountSheetView: View {
    @Bindable var state: AppState
    @Bindable var draft: AddAccountDraftModel

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Add Account")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Button("Cancel") {
                    state.activeModal = nil
                }
                .buttonStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

                Button("Add") {
                    state.addAccount(draft.buildProfile())
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    fieldRow("Provider") {
                        Picker("", selection: $draft.provider) {
                            ForEach(ProviderID.allCases) { p in
                                Text(p.displayName).tag(p)
                            }
                        }
                        .labelsHidden()
                        .onChange(of: draft.provider) { _, newValue in
                            draft.applyProviderDefaults(newValue)
                        }
                    }

                    fieldRow("Display Name") {
                        TextField("e.g. Work Account", text: $draft.displayName)
                            .textFieldStyle(.roundedBorder)
                    }

                    fieldRow("Email (optional)") {
                        TextField("name@gmail.com", text: $draft.email)
                            .textFieldStyle(.roundedBorder)
                    }

                    fieldRow("Plan Name") {
                        TextField(draft.provider.defaultPlanName, text: $draft.planName)
                            .textFieldStyle(.roundedBorder)
                    }

                    fieldRow("Monthly Fee ($)") {
                        TextField("20.00", text: $draft.monthlyFeeText)
                            .textFieldStyle(.roundedBorder)
                    }

                    Toggle("Mark as Active Account", isOn: $draft.isActive)
                        .font(.system(size: 11.5))

                    Divider().padding(.vertical, 2)

                    Text("Optional Overrides (Read-Only)")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)

                    fieldRow("Custom Log Dir") {
                        TextField("~/.claude-work", text: $draft.customLogDir)
                            .textFieldStyle(.roundedBorder)
                    }

                    fieldRow("Credential JSON") {
                        TextField("~/.codex/auth.json", text: $draft.credentialPath)
                            .textFieldStyle(.roundedBorder)
                    }

                    fieldRow("Quota JSON File") {
                        TextField("~/Library/.../quota.json", text: $draft.externalQuotaFilePath)
                            .textFieldStyle(.roundedBorder)
                    }

                    fieldRow("Quota Command") {
                        TextField("openusage antigravity --json", text: $draft.externalQuotaCommand)
                            .textFieldStyle(.roundedBorder)
                    }
                }
                .padding(14)
            }
        }
        .font(.system(size: 11.5))
    }

    private func fieldRow<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 10) {
            Text(label)
                .frame(width: 108, alignment: .leading)
                .foregroundStyle(.secondary)
            content()
        }
    }
}
