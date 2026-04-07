import SwiftUI

/// Shown on first launch so the user can pick a display name before chatting.
/// Setting a name here avoids broadcasting the device name (e.g. "John's iPhone"),
/// which protects the user's privacy right from the start.
struct OnboardingView: View {
    @EnvironmentObject private var multipeerSession: MultipeerSession
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    @State private var displayName = ""

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
                    .submitLabel(.go)
                    .onSubmit(completeOnboarding)
                Text("Visible to nearby devices. Choose something that doesn't reveal personal information.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 32)

            Spacer()

            Button(action: completeOnboarding) {
                Text("Get Started")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(isValid ? Color.blue : Color.gray.opacity(0.4))
                    .foregroundStyle(isValid ? .white : .secondary)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .disabled(!isValid)
            .padding(.horizontal, 32)
            .padding(.bottom, 40)
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
