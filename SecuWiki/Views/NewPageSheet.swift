import SwiftUI
import AppKit

/// Fenêtre « Nouvelle page » : titre + choix du modèle (Cmd+N).
/// Les modèles proposés se règlent dans Réglages > Modèles et variables.
struct NewPageSheet: View {
    @Environment(WikiStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openSettings) private var openSettings
    @State private var folder: URL
    @State private var title = ""
    @State private var template = ""
    @FocusState private var isTitleFocused: Bool

    init(folder: URL) {
        _folder = State(initialValue: folder)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Nouvelle page")
                .font(.title3.weight(.semibold))
            LocationPicker(selection: $folder)

            TextField("Titre de la page", text: $title, prompt: Text("Ex. : Lab – Scan Nmap"))
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 14))
                .focused($isTitleFocused)
                .onSubmit(create)

            Text("Modèle")
                .font(.subheadline.weight(.medium))
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 8)], spacing: 8) {
                    TemplateTile(title: "Page vide", icon: "doc", isSelected: template.isEmpty) {
                        template = ""
                    }
                    ForEach(store.creationTemplates) { command in
                        TemplateTile(title: command.title, icon: command.icon, isSelected: template == command.trigger) {
                            template = command.trigger
                        }
                    }
                }
                .padding(2)
            }
            .frame(height: 210)

            HStack {
                Button("Gérer les modèles…") {
                    dismiss()
                    openSettings()
                }
                .buttonStyle(.link)
                Spacer()
                Button("Annuler", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Créer", action: create)
                    .keyboardShortcut(.defaultAction)
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 520)
        .onAppear {
            // Modèle par défaut (Réglages), s'il est toujours proposé.
            let preferred = store.wikiSettings.defaultTemplate
            template = store.creationTemplates.contains { $0.trigger == preferred } ? preferred : ""
            isTitleFocused = true
        }
    }

    private func create() {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        dismiss()
        store.createPage(titled: trimmed, in: folder, template: template)
    }
}

/// Choix de l'emplacement : racine du wiki ou n'importe quel dossier.
struct LocationPicker: View {
    @Environment(WikiStore.self) private var store
    @Binding var selection: URL

    var body: some View {
        Picker(selection: $selection) {
            ForEach(store.locationOptions) { option in
                Label(option.label, systemImage: option.url == store.rootURL ? "books.vertical" : "folder")
                    .tag(option.url)
            }
        } label: {
            Text("Dans").foregroundStyle(.secondary)
        }
        .fixedSize()
    }
}

/// Fenêtre « Nouveau dossier » (Cmd+Maj+N) : nom + emplacement.
struct NewFolderSheet: View {
    @Environment(WikiStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var folder: URL
    @State private var name = ""
    @FocusState private var isNameFocused: Bool

    init(folder: URL) {
        _folder = State(initialValue: folder)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Nouveau dossier")
                .font(.title3.weight(.semibold))
            LocationPicker(selection: $folder)
            TextField("Nom du dossier", text: $name, prompt: Text("Ex. : 06_Gestion des risques"))
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 14))
                .focused($isNameFocused)
                .onSubmit(create)
            HStack {
                Spacer()
                Button("Annuler", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Créer", action: create)
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 440)
        .onAppear { isNameFocused = true }
    }

    private func create() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        dismiss()
        store.createFolder(named: trimmed, in: folder)
    }
}

/// Une vignette de modèle.
private struct TemplateTile: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .frame(width: 20)
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                Text(title)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .frame(height: 44)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.accentColor : Color.primary.opacity(0.1), lineWidth: isSelected ? 1.5 : 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
