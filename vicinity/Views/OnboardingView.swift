import SwiftUI

/// Shown on first launch so the user can pick a display name before chatting.
/// Setting a name here avoids broadcasting the device name (e.g. "John's iPhone"),
/// which protects the user's privacy right from the start.
struct OnboardingView: View {
    @EnvironmentObject private var multipeerSession: MultipeerSession
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    @State private var displayName = ""
    @State private var step: Step = .name

    private enum Step { case name, permissions }

    private var isValid: Bool {
        !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.system(size: 72))
                .foregroundStyle(.blue)
                .padding(.bottom, 24)

            switch step {
            case .name:
                nameStep
            case .permissions:
                permissionsStep
            }

            Spacer()

            Button(action: primaryAction) {
                Text(step == .name ? "Continue" : "Get Started")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(canAdvance ? Color.blue : Color.gray.opacity(0.4))
                    .foregroundStyle(canAdvance ? .white : .secondary)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .disabled(!canAdvance)
            .padding(.horizontal, 32)
            .padding(.bottom, 40)
        }
    }

    private var canAdvance: Bool {
        switch step {
        case .name: return isValid
        case .permissions: return true
        }
    }

    @ViewBuilder
    private var nameStep: some View {
        Text("Welcome to Vicinity")
            .font(.largeTitle)
            .fontWeight(.bold)
            .padding(.bottom, 12)

        Text("Chat with nearby people over Bluetooth and Wi-Fi — no internet, no accounts, no tracking.")
            .font(.body)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 40)
            .padding(.bottom, 48)

        VStack(alignment: .leading, spacing: 8) {
            Text("Your Display Name")
                .font(.headline)
            TextField("e.g. Alice", text: $displayName)
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
                .submitLabel(.next)
                .onSubmit(primaryAction)
            Text("Visible to nearby devices. Choose something that doesn't reveal personal information.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 32)
    }

    @ViewBuilder
    private var permissionsStep: some View {
        Text("Almost there")
            .font(.largeTitle)
            .fontWeight(.bold)
            .padding(.bottom, 12)

        Text("Vicinity needs Bluetooth and Local Network access to find people nearby. iOS will ask for both on the next screen — please allow them so the app can work.")
            .font(.body)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 32)
            .padding(.bottom, 24)

        VStack(alignment: .leading, spacing: 16) {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Bluetooth").font(.subheadline).fontWeight(.semibold)
                    Text("Used to discover nearby devices and wake the app for scheduled messages.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: "dot.radiowaves.left.and.right").foregroundStyle(.blue)
            }
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Local Network").font(.subheadline).fontWeight(.semibold)
                    Text("Used to exchange messages over peer-to-peer Wi-Fi when available.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: "wifi").foregroundStyle(.blue)
            }
        }
        .padding(.horizontal, 40)
    }

    private func primaryAction() {
        switch step {
        case .name:
            guard isValid else { return }
            step = .permissions
        case .permissions:
            completeOnboarding()
        }
    }

    private func completeOnboarding() {
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        multipeerSession.updateDisplayName(trimmed)
        UserDefaults.standard.set(trimmed, forKey: "displayName")
        hasCompletedOnboarding = true
    }
}

#Preview {
    OnboardingView()
        .environmentObject(MultipeerSession())
}
