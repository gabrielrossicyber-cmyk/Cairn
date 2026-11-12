import SwiftUI

/// Écran affiché à la place d'une page verrouillée.
struct LockedPageView: View {
    @Environment(WikiStore.self) private var store
    let title: String
    @State private var password = ""
    @State private var errorText: String?
    @State private var isWorking = false
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "lock")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.title2.weight(.semibold))
            Text("Cette page est verrouillée.")
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                SecureField("Mot de passe", text: $password)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 240)
                    .focused($isFocused)
                    .onSubmit(unlock)
                    .disabled(isWorking)
                Button("Déverrouiller", action: unlock)
                    .keyboardShortcut(.defaultAction)
                    .disabled(password.isEmpty || isWorking)
            }
            .padding(.top, 6)
            ZStack {
                if isWorking {
                    ProgressView().controlSize(.small)
                } else if let errorText {
                    Text(errorText)
                        .font(.callout)
                        .foregroundStyle(.red)
                }
            }
            .frame(height: 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { isFocused = true }
        .onChange(of: store.openURL) {
            password = ""
            errorText = nil
        }
    }

    private func unlock() {
        guard !password.isEmpty, !isWorking else { return }
        let attempt = password
        isWorking = true
        errorText = nil
        Task {
            do {
                try await store.unlockOpenPage(password: attempt)
            } catch {
                errorText = error.localizedDescription
                isFocused = true
            }
            password = ""
            isWorking = false
        }
    }
}

/// Fenêtre « Verrouiller avec un mot de passe ».
struct SetPasswordSheet: View {
    @Environment(WikiStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var password = ""
    @State private var confirmation = ""
    @State private var errorText: String?
    @State private var isWorking = false

    private var problem: String? {
        if password.count < PageCrypto.minimumPasswordLength {
            return "Au moins \(PageCrypto.minimumPasswordLength) caractères."
        }
        if confirmation != password { return "Les deux mots de passe ne correspondent pas." }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Verrouiller la page")
                .font(.title3.weight(.semibold))
            Text("Le contenu est chiffré sur le disque (AES-256-GCM). Seul le titre reste visible dans l'arborescence et la recherche.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            SecureField("Mot de passe", text: $password)
            SecureField("Confirmer le mot de passe", text: $confirmation)
                .onSubmit(lock)

            if !password.isEmpty, !confirmation.isEmpty, let problem {
                Text(problem).font(.caption).foregroundStyle(.secondary)
            }

            Label("Aucune récupération possible : mot de passe perdu = page perdue. Range-le dans ton gestionnaire de mots de passe.",
                  systemImage: "exclamationmark.triangle")
                .font(.callout)
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)

            if let errorText {
                Text(errorText).font(.callout).foregroundStyle(.red)
            }

            HStack {
                if isWorking { ProgressView().controlSize(.small) }
                Spacer()
                Button("Annuler") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Verrouiller", action: lock)
                    .keyboardShortcut(.defaultAction)
                    .disabled(problem != nil || isWorking)
            }
        }
        .textFieldStyle(.roundedBorder)
        .padding(22)
        .frame(width: 420)
    }

    private func lock() {
        guard problem == nil, !isWorking else { return }
        isWorking = true
        let chosen = password
        Task {
            if let failure = await store.lockOpenPage(password: chosen) {
                errorText = failure
                isWorking = false
            } else {
                dismiss()
            }
        }
    }
}
