import AppKit
import SwiftUI

/// Réglages › Raccourcis : changer, retirer ou rétablir le raccourci clavier de chaque action.
struct ShortcutsSettings: View {
    @AppStorage(Prefs.shortcuts) private var json = ""
    /// Action dont on attend le nouveau raccourci (une seule à la fois).
    @State private var recording: ShortcutAction?
    @State private var monitor: Any?
    @State private var message: (action: ShortcutAction, text: String)?
    /// Combinaison déjà prise par une autre action : on demande avant de la lui retirer.
    @State private var pendingConflict: Conflict?

    private struct Conflict: Identifiable {
        let action: ShortcutAction
        let combo: KeyCombo
        let other: ShortcutAction
        var id: String { action.rawValue }
    }

    private var settings: ShortcutSettings { ShortcutSettings.load(from: json) }

    var body: some View {
        Form {
            Section {
                Text("Clique sur un raccourci puis tape la nouvelle combinaison. Échap annule, ⌫ retire le raccourci. Une combinaison doit utiliser ⌘ ou ⌃ (ou une touche F1…F20).")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            ForEach(ShortcutAction.Group.allCases, id: \.self) { group in
                Section(group.rawValue) {
                    ForEach(ShortcutAction.allCases.filter { $0.group == group }) { action in
                        row(action)
                    }
                    if group == .global {
                        Text("Fonctionne depuis n'importe quelle app tant que « Capture rapide » est activée dans Général.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Section {
                HStack {
                    Spacer()
                    Button("Tout réinitialiser") {
                        stopRecording()
                        message = nil
                        json = ""
                    }
                    .disabled(!settings.hasChanges)
                }
            }
        }
        .formStyle(.grouped)
        .onDisappear(perform: stopRecording)
        .confirmationDialog(
            pendingConflict.map { "\($0.combo.display) est déjà utilisé par « \($0.other.title) »" } ?? "",
            isPresented: Binding(get: { pendingConflict != nil }, set: { if !$0 { pendingConflict = nil } }),
            presenting: pendingConflict
        ) { conflict in
            Button("L'attribuer à « \(conflict.action.title) »") {
                var updated = settings
                updated.set(nil, for: conflict.other)
                updated.set(conflict.combo, for: conflict.action)
                json = updated.json
                message = (conflict.action, "« \(conflict.other.title) » n'a plus de raccourci.")
            }
            Button("Annuler", role: .cancel) {}
        } message: { conflict in
            Text("« \(conflict.other.title) » n'aura plus de raccourci. Tu pourras lui en donner un autre ensuite.")
        }
    }

    // MARK: Ligne

    private func row(_ action: ShortcutAction) -> some View {
        let isRecording = recording == action
        let combo = settings.combo(for: action)
        return VStack(alignment: .trailing, spacing: 4) {
            HStack {
                Text(action.title)
                Spacer()
                Button {
                    isRecording ? stopRecording() : startRecording(action)
                } label: {
                    Text(isRecording ? "Tape le raccourci…" : (combo?.display ?? "Aucun"))
                        .font(isRecording ? .callout : .system(.body, design: .rounded).weight(.medium))
                        .foregroundStyle(isRecording ? Color.accentColor : (combo == nil ? .secondary : .primary))
                        .frame(minWidth: 120)
                        .padding(.vertical, 3)
                        .padding(.horizontal, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(isRecording ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.06))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .strokeBorder(isRecording ? Color.accentColor : Color.clear, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .help(isRecording ? "Échap : annuler · ⌫ : retirer le raccourci" : "Cliquer pour changer")

                Button {
                    var updated = settings
                    updated.reset(action)
                    json = updated.json
                    if message?.action == action { message = nil }
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                }
                .buttonStyle(.borderless)
                .help("Rétablir \(action.defaultCombo.display)")
                .opacity(settings.isDefault(action) ? 0 : 1)
                .disabled(settings.isDefault(action))
            }
            if let message, message.action == action {
                Text(message.text)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    // MARK: Enregistrement d'une combinaison

    private func startRecording(_ action: ShortcutAction) {
        stopRecording()
        message = nil
        recording = action
        // Le raccourci global ne doit pas ouvrir la capture pendant qu'on tape une combinaison.
        QuickCaptureController.shared.suspendHotKey(true)
        // Moniteur local : la frappe est lue AVANT les menus, donc ⌘N n'ouvre pas une nouvelle page.
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handle(event, for: action)
            return nil
        }
    }

    private func stopRecording() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if recording != nil { QuickCaptureController.shared.suspendHotKey(false) }
        recording = nil
    }

    private func handle(_ event: NSEvent, for action: ShortcutAction) {
        let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
        let code = Int(event.keyCode)
        if flags.isEmpty, code == 53 { // Échap
            stopRecording()
            return
        }
        if flags.isEmpty, code == 51 || code == 117 { // ⌫ / ⌦ : aucun raccourci
            var updated = settings
            updated.set(nil, for: action)
            json = updated.json
            stopRecording()
            return
        }
        guard let combo = KeyCombo(event: event) else { return }
        switch settings.problem(with: combo, for: action) {
        case .unusable:
            message = (action, "Ajoute ⌘ ou ⌃ : une touche seule empêcherait d'écrire.")
            return // on reste en écoute
        case .reserved:
            message = (action, "\(combo.display) est réservé par macOS ou l'édition de texte.")
            return
        case .usedBy(let other):
            stopRecording()
            pendingConflict = Conflict(action: action, combo: combo, other: other)
        case nil:
            var updated = settings
            updated.set(combo, for: action)
            json = updated.json
            message = nil
            stopRecording()
        }
    }
}
