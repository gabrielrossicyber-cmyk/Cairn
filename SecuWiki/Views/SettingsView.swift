import SwiftUI
import AppKit

/// Fenêtre Réglages (Cmd+,).
struct SettingsView: View {
    @Environment(WikiStore.self) private var store

    var body: some View {
        TabView {
            GeneralSettings()
                .tabItem { Label("Général", systemImage: "gearshape") }
            EditorSettings()
                .tabItem { Label("Éditeur", systemImage: "pencil") }
            PreviewSettings()
                .tabItem { Label("Aperçu", systemImage: "eye") }
            TemplatesSettings()
                .tabItem { Label("Modèles et variables", systemImage: "curlybraces") }
            ExportSettings()
                .tabItem { Label("Export", systemImage: "square.and.arrow.up") }
        }
        .frame(width: 580, height: 460)
        // Toute modification des réglages du wiki est enregistrée dans .secuwiki.json.
        .onChange(of: store.wikiSettings) { store.saveWikiSettings() }
    }
}

// MARK: Général

private struct GeneralSettings: View {
    @Environment(WikiStore.self) private var store
    @AppStorage(Prefs.defaultMode) private var defaultMode = Prefs.Defaults.defaultMode
    @AppStorage(Prefs.appearance) private var appearance = Prefs.Defaults.appearance

    var body: some View {
        @Bindable var store = store

        Form {
            Section {
                if let root = store.rootURL {
                    TextField("Nom du wiki", text: $store.wikiSettings.name, prompt: Text(root.lastPathComponent))
                    LabeledContent("Dossier") {
                        Text(root.path)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                    }
                    HStack {
                        Button("Afficher dans le Finder") { NSWorkspace.shared.activateFileViewerSelecting([root]) }
                        Spacer()
                        Button("Nouveau wiki…") { store.createWiki() }
                        Button("Ouvrir un autre wiki…") { store.chooseFolder() }
                    }
                } else {
                    Text("Aucun wiki ouvert.")
                    HStack {
                        Button("Créer un wiki…") { store.createWiki() }
                        Button("Ouvrir un wiki existant…") { store.chooseFolder() }
                    }
                }
            } header: {
                Text("Wiki")
            } footer: {
                Text("Le nom est enregistré dans le dossier du wiki : il te suivra sur tous tes appareils.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Apparence") {
                Picker("Thème", selection: $appearance) {
                    Text("Comme le système").tag("system")
                    Text("Clair").tag("light")
                    Text("Sombre").tag("dark")
                }
                .pickerStyle(.segmented)
            }

            Section("Démarrage") {
                Picker("Mode à l'ouverture de l'app", selection: $defaultMode) {
                    ForEach(EditorMode.allCases) { mode in
                        Text(mode.label).tag(mode.rawValue)
                    }
                }
            }

            Section("Barre latérale") {
                LabeledContent("Pages récentes") {
                    Button("Effacer la liste") { store.clearRecents() }
                        .disabled(store.recents.isEmpty)
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: Éditeur

private struct EditorSettings: View {
    @AppStorage(Prefs.editorFontSize) private var fontSize = Prefs.Defaults.editorFontSize
    @AppStorage(Prefs.autosaveDelay) private var autosaveDelay = Prefs.Defaults.autosaveDelay

    var body: some View {
        Form {
            Section("Texte") {
                LabeledContent("Taille de la police") {
                    HStack {
                        Slider(value: $fontSize, in: 11...20, step: 1)
                            .frame(width: 200)
                        Text("\(Int(fontSize)) pt")
                            .monospacedDigit()
                            .frame(width: 44, alignment: .trailing)
                    }
                }
            }
            Section {
                Picker("Enregistrement automatique", selection: $autosaveDelay) {
                    Text("Immédiat (0,5 s)").tag(0.5)
                    Text("1 seconde").tag(1.0)
                    Text("2 secondes").tag(2.0)
                    Text("5 secondes").tag(5.0)
                }
            } header: {
                Text("Enregistrement")
            } footer: {
                Text("Délai après la dernière frappe. La page est aussi enregistrée quand tu changes de page ou d'app, et avec Cmd+S.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: Aperçu

private struct PreviewSettings: View {
    @AppStorage(Prefs.previewFontSize) private var fontSize = Prefs.Defaults.previewFontSize
    @AppStorage(Prefs.previewMaxWidth) private var maxWidth = Prefs.Defaults.previewMaxWidth
    @AppStorage(Prefs.lineBreaks) private var lineBreaks = Prefs.Defaults.lineBreaks
    @AppStorage(Prefs.autoVerticalDiagrams) private var autoVertical = Prefs.Defaults.autoVerticalDiagrams

    var body: some View {
        Form {
            Section("Lecture") {
                LabeledContent("Taille du texte") {
                    HStack {
                        Slider(value: $fontSize, in: 12...20, step: 1)
                            .frame(width: 200)
                        Text("\(Int(fontSize)) px")
                            .monospacedDigit()
                            .frame(width: 44, alignment: .trailing)
                    }
                }
                Picker("Largeur du texte", selection: $maxWidth) {
                    Text("Étroite").tag(700.0)
                    Text("Normale").tag(860.0)
                    Text("Large").tag(1100.0)
                    Text("Toute la largeur").tag(0.0)
                }
            }
            Section("Mise en forme") {
                Toggle("Un retour à la ligne dans l'éditeur = un retour à la ligne à l'affichage", isOn: $lineBreaks)
                Toggle("Schémas horizontaux trop larges : les afficher de haut en bas", isOn: $autoVertical)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: Modèles et variables globales

private struct TemplatesSettings: View {
    @Environment(WikiStore.self) private var store

    var body: some View {
        @Bindable var store = store

        Form {
            Section {
                Picker("Modèle présélectionné", selection: $store.wikiSettings.defaultTemplate) {
                    Text("Page vide").tag("")
                    ForEach(store.templateOptions) { command in
                        Text(command.title).tag(command.trigger)
                    }
                }
            } header: {
                Text("Nouvelle page (Cmd+N)")
            } footer: {
                Text("Sélectionné par défaut dans la fenêtre « Nouvelle page ». Tu peux toujours choisir un autre modèle, ou en insérer un avec « / ».")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                ForEach(store.templateOptions) { command in
                    Toggle(isOn: Binding(
                        get: { !store.wikiSettings.hiddenTemplates.contains(command.trigger) },
                        set: { shown in
                            store.wikiSettings.hiddenTemplates.removeAll { $0 == command.trigger }
                            if !shown { store.wikiSettings.hiddenTemplates.append(command.trigger) }
                        }
                    )) {
                        Label(command.title, systemImage: command.icon)
                    }
                }
            } header: {
                Text("Modèles proposés à la création")
            } footer: {
                Text("Décoche ceux que tu n'utilises pas : ils restent disponibles avec « / » dans l'éditeur.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                if let folder = store.templatesFolderURL {
                    LabeledContent("Dossier", value: folder.lastPathComponent)
                    LabeledContent("Modèles trouvés", value: "\(store.customTemplates.count)")
                    Button("Afficher dans le Finder") { NSWorkspace.shared.activateFileViewerSelecting([folder]) }
                } else {
                    Button("Créer le dossier _Modèles") { store.createTemplatesFolder() }
                        .disabled(store.rootURL == nil)
                }
            } header: {
                Text("Mes modèles")
            } footer: {
                Text("Chaque fichier .md du dossier _Modèles devient un modèle : il apparaît ci-dessus, dans « Nouvelle page » et dans le menu « / » (le nom du fichier sert de commande : Rapport-pentest.md -> /rapportpentest). Utilise ⟦texte⟧ pour le texte à sélectionner après insertion.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                ForEach($store.wikiSettings.globalVariables) { $variable in
                    HStack {
                        TextField("NOM", text: $variable.name, prompt: Text("NOM"))
                            .font(.system(.body, design: .monospaced))
                            .frame(width: 160)
                        TextField("valeur", text: $variable.value, prompt: Text("valeur"))
                            .font(.system(.body, design: .monospaced))
                        Button {
                            store.wikiSettings.globalVariables.removeAll { $0.id == variable.id }
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .foregroundStyle(.red)
                        }
                        .buttonStyle(.borderless)
                        .help("Supprimer la variable")
                    }
                    .labelsHidden()
                }
                Button {
                    store.wikiSettings.globalVariables.append(GlobalVariable(name: "", value: ""))
                } label: {
                    Label("Ajouter une variable", systemImage: "plus.circle")
                }
            } header: {
                Text("Variables globales")
            } footer: {
                Text("Disponibles dans toutes les pages avec {{NOM}} (lettres, chiffres et _ uniquement). Exemples : KALI_IP, DOMAINE_LAB, DC_IP. Une variable définie dans la page est prioritaire.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: Export

private struct ExportSettings: View {
    @AppStorage(Prefs.pdfPaper) private var paper = Prefs.Defaults.pdfPaper
    @AppStorage(Prefs.pdfShowAnswers) private var showAnswers = Prefs.Defaults.pdfShowAnswers

    var body: some View {
        Form {
            Section("PDF et impression") {
                Picker("Format du papier", selection: $paper) {
                    Text("A4 (Europe)").tag("A4")
                    Text("Letter (US)").tag("Letter")
                }
                Toggle("Inclure les réponses masquées (/question, /reponse)", isOn: $showAnswers)
                Text("Désactive cette option pour imprimer une fiche de questions sans les réponses.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
