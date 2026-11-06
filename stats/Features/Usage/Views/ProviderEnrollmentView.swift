import SwiftUI

/// First-launch provider selection. Shows only choices and support-state indicators;
/// collection/privacy disclosure lives in provider detail settings.
struct ProviderEnrollmentView: View {
    @Bindable var store: UsageStore
    var onFinished: () -> Void

    @State private var selection: Set<UsageProviderIdentity> = []

    var body: some View {
        VStack(spacing: 0) {
            header
            Form {
                Section {
                    ForEach(ProviderCatalog.enrollableProviders) { provider in
                        enrollmentRow(ProviderCatalog.descriptor(for: provider))
                    }
                } header: {
                    Text("Providers")
                } footer: {
                    Text("Choose sources to track. You can change this later in Settings. Collection details appear when you open a provider.")
                }
            }
            .formStyle(.grouped)
            footer
        }
        .frame(width: 420, height: 460)
        .onAppear {
            selection = Set(UsageProviderIdentity.allCases.filter { store.isProviderEnrolled($0) })
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Choose providers")
                .font(.title2.weight(.semibold))
            Text("Select which LLM sources to enable. Supported sources have no badge; Experimental and Detected use colored icons.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 8)
    }

    private func enrollmentRow(_ descriptor: ProviderDescriptor) -> some View {
        let provider = descriptor.identity
        let isOn = selection.contains(provider)
        return Button {
            if isOn {
                selection.remove(provider)
            } else {
                selection.insert(provider)
            }
        } label: {
            HStack(spacing: 12) {
                Image(provider.logoAssetName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 22, height: 22)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(provider.name)
                            .font(.body.weight(.medium))
                            .foregroundStyle(.primary)
                        ProviderSupportStateIndicator(state: descriptor.supportState)
                    }
                    Text(descriptor.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 8)
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isOn ? Color.accentColor : Color.secondary)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(provider.name), \(descriptor.supportState.accessibilityLabel)")
        .accessibilityValue(isOn ? "Selected" : "Not selected")
        .accessibilityHint(descriptor.supportState.tooltip)
        .accessibilityAddTraits(isOn ? [.isSelected] : [])
    }

    private var footer: some View {
        HStack {
            Button("Skip for now") {
                store.skipProviderEnrollment()
                onFinished()
            }
            .keyboardShortcut(.cancelAction)
            .accessibilityHint("Finish without enabling providers. You can enroll later in Settings.")

            Spacer()

            Button("Continue") {
                store.completeProviderEnrollment(selection)
                onFinished()
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .accessibilityHint("Save the selected providers and continue.")
        }
        .padding(16)
    }
}
