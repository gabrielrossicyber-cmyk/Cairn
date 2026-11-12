import SwiftUI

/// Tableau de bord : affiché quand aucune page n'est ouverte (Cmd+Maj+D).
/// Composé de widgets que l'on ajoute, retire, déplace et règle (« Personnaliser »).
/// La disposition est propre à chaque wiki (fichier .secuwiki.json).
struct DashboardView: View {
    @Environment(WikiStore.self) private var store
    @State private var isEditing = false

    var body: some View {
        let stats = DashboardStats(entries: store.searchIndex)
        let widgets = store.dashboardWidgets
        let rows = Self.rows(widgets)

        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header

                if widgets.isEmpty {
                    ContentUnavailableView {
                        Label("Tableau de bord vide", systemImage: "square.grid.2x2")
                    } description: {
                        Text("Ajoute des widgets avec « Personnaliser ».")
                    }
                    .padding(.top, 40)
                }

                ForEach(rows) { row in
                    HStack(alignment: .top, spacing: 16) {
                        ForEach(row.widgets) { widget in
                            WidgetCard(
                                widget: widget,
                                stats: stats,
                                isEditing: isEditing,
                                isFirst: widget.id == widgets.first?.id,
                                isLast: widget.id == widgets.last?.id
                            )
                        }
                        // Demi-widget seul sur sa ligne : il garde sa demi-largeur.
                        if row.widgets.count == 1, !row.widgets[0].wide {
                            Color.clear.frame(maxWidth: .infinity, maxHeight: 1)
                        }
                    }
                }
            }
            .padding(28)
            .frame(maxWidth: 1000, alignment: .leading)
            .frame(maxWidth: .infinity)
            .animation(.easeInOut(duration: 0.2), value: widgets)
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(store.wikiDisplayName)
                    .font(.largeTitle.weight(.bold))
                Text("Tableau de bord")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if isEditing {
                Menu {
                    ForEach(DashboardWidget.Kind.allCases) { kind in
                        Button { store.addWidget(kind) } label: {
                            Label(kind.label, systemImage: kind.icon)
                        }
                    }
                } label: {
                    Label("Ajouter un widget", systemImage: "plus")
                }
                .fixedSize()
                Button("Réinitialiser") { store.resetDashboard() }
                    .help("Revenir à la disposition par défaut")
            }
            Button(isEditing ? "Terminer" : "Personnaliser") { isEditing.toggle() }
                .buttonStyle(.bordered)
                .keyboardShortcut(isEditing ? .defaultAction : nil)
        }
    }

    /// Lignes de la grille : un widget large occupe sa ligne, deux demi-widgets se partagent une ligne.
    private struct Row: Identifiable {
        let widgets: [DashboardWidget]
        var id: UUID { widgets[0].id }
    }

    private static func rows(_ widgets: [DashboardWidget]) -> [Row] {
        var rows: [Row] = []
        var pending: DashboardWidget?
        for widget in widgets {
            if widget.wide {
                if let half = pending { rows.append(Row(widgets: [half])); pending = nil }
                rows.append(Row(widgets: [widget]))
            } else if let half = pending {
                rows.append(Row(widgets: [half, widget]))
                pending = nil
            } else {
                pending = widget
            }
        }
        if let half = pending { rows.append(Row(widgets: [half])) }
        return rows
    }
}

// MARK: Carte d'un widget

private struct WidgetCard: View {
    @Environment(WikiStore.self) private var store
    let widget: DashboardWidget
    let stats: DashboardStats
    let isEditing: Bool
    let isFirst: Bool
    let isLast: Bool
    @State private var isConfiguring = false

    /// Les chiffres clés s'affichent sans cadre ni titre (sauf en personnalisation).
    private var framed: Bool { widget.kind != .stats || isEditing }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if framed {
                HStack(spacing: 8) {
                    Label(widget.displayTitle, systemImage: widget.kind.icon)
                        .font(.headline)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    if isEditing { editControls }
                }
            }
            WidgetContent(widget: widget, stats: stats)
        }
        .padding(framed ? 16 : 0)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            if framed {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isEditing ? Color.accentColor.opacity(0.6) : Color.primary.opacity(0.08),
                            style: StrokeStyle(lineWidth: 1, dash: isEditing ? [5, 4] : []))
            }
        }
    }

    private var editControls: some View {
        HStack(spacing: 2) {
            control("arrow.up", help: "Monter") { store.moveWidget(widget.id, by: -1) }
                .disabled(isFirst)
            control("arrow.down", help: "Descendre") { store.moveWidget(widget.id, by: 1) }
                .disabled(isLast)
            control(widget.wide ? "rectangle.split.2x1" : "rectangle",
                    help: widget.wide ? "Passer en demi-largeur" : "Passer en pleine largeur") {
                var copy = widget
                copy.wide.toggle()
                store.updateWidget(copy)
            }
            control("slider.horizontal.3", help: "Régler") { isConfiguring = true }
                .popover(isPresented: $isConfiguring, arrowEdge: .bottom) {
                    WidgetSettingsView(widget: widget)
                }
            control("trash", help: "Retirer") { store.removeWidget(widget.id) }
        }
    }

    private func control(_ icon: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .help(help)
    }
}

// MARK: Contenu des widgets

private struct WidgetContent: View {
    @Environment(WikiStore.self) private var store
    let widget: DashboardWidget
    let stats: DashboardStats

    var body: some View {
        switch widget.kind {
        case .stats:
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 12)], spacing: 12) {
                StatTile(value: stats.pageCount, label: "pages", icon: "doc.text")
                StatTile(value: stats.sections.count, label: "sections", icon: "folder")
                StatTile(value: stats.openTasks.count, label: "tâches à faire", icon: "checklist")
                StatTile(value: stats.questionCount, label: "questions de révision", icon: "questionmark.bubble")
            }

        case .countdown:
            CountdownContent(date: widget.date)

        case .question:
            QuestionContent(entries: store.entries(inFolder: widget.folder))

        case .tasks:
            TaskList(tasks: widget.folder.isEmpty
                        ? stats.openTasks
                        : DashboardStats(entries: store.entries(inFolder: widget.folder)).openTasks,
                     limit: widget.limit)

        case .recent:
            RecentList(entries: store.entries(inFolder: widget.folder), limit: widget.limit)

        case .favorites:
            FavoriteList(limit: widget.limit)

        case .folder:
            FolderList(folder: widget.folder, limit: widget.limit)

        case .sections:
            SectionsChart(sections: stats.sections)

        case .note:
            NoteContent(text: widget.text)
        }
    }
}

private struct TaskList: View {
    @Environment(WikiStore.self) private var store
    let tasks: [DashboardStats.OpenTask]
    let limit: Int

    var body: some View {
        if tasks.isEmpty {
            EmptyHint("Aucune case « - [ ] » non cochée. Bravo !")
        } else {
            LimitedList(total: tasks.count, limit: limit) {
                ForEach(tasks.prefix(limit)) { task in
                    PageLink(title: task.text, detail: task.page.title, icon: "square") {
                        store.openPage(task.page.url)
                    }
                }
            }
        }
    }
}

private struct RecentList: View {
    @Environment(WikiStore.self) private var store
    let entries: [SearchEntry]
    let limit: Int

    var body: some View {
        let recent = entries.sorted { ($0.modified ?? .distantPast) > ($1.modified ?? .distantPast) }
        if recent.isEmpty {
            EmptyHint("Aucune page pour l'instant.")
        } else {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(recent.prefix(limit)) { entry in
                    PageLink(title: entry.title, detail: entry.modified.map(Self.relative) ?? entry.path) {
                        store.openPage(entry.url)
                    }
                }
            }
        }
    }

    private static func relative(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "fr_CH")
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: .now)
    }
}

private struct FavoriteList: View {
    @Environment(WikiStore.self) private var store
    let limit: Int

    var body: some View {
        let favorites = store.favoriteNodes
        if favorites.isEmpty {
            EmptyHint("Aucun favori. Cmd+D sur une page pour l'ajouter.")
        } else {
            LimitedList(total: favorites.count, limit: limit) {
                ForEach(favorites.prefix(limit)) { node in
                    PageLink(title: node.name, detail: "", icon: "star") {
                        if let page = node.pageURL { store.openPage(page) }
                    }
                }
            }
        }
    }
}

private struct FolderList: View {
    @Environment(WikiStore.self) private var store
    let folder: String
    let limit: Int

    var body: some View {
        if folder.isEmpty {
            EmptyHint("Choisis un dossier : « Personnaliser », puis le bouton de réglages du widget.")
        } else {
            let pages = store.entries(inFolder: folder)
                .sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
            if pages.isEmpty {
                EmptyHint("Ce dossier ne contient aucune page.")
            } else {
                LimitedList(total: pages.count, limit: limit) {
                    ForEach(pages.prefix(limit)) { entry in
                        PageLink(title: entry.title, detail: "", icon: entry.isLocked ? "lock.doc" : "doc.text") {
                            store.openPage(entry.url)
                        }
                    }
                }
            }
        }
    }
}

private struct NoteContent: View {
    let text: String

    var body: some View {
        let markdown = (try? AttributedString(
            markdown: text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(text)
        Text(markdown)
            .font(.callout)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Compte à rebours en jours (J-482).
private struct CountdownContent: View {
    let date: Date?

    var body: some View {
        if let date {
            let calendar = Calendar.current
            let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: .now),
                                               to: calendar.startOfDay(for: date)).day ?? 0
            VStack(alignment: .leading, spacing: 4) {
                Text(days > 0 ? "J-\(days)" : days == 0 ? "Aujourd'hui" : "Passé")
                    .font(.system(size: 40, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(Color.accentColor)
                Text(date.formatted(.dateTime.day().month(.wide).year().locale(Locale(identifier: "fr_CH"))))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                if days > 13 {
                    Text("≈ \(days / 7) semaines")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } else {
            EmptyHint("Choisis une date dans les réglages du widget.")
        }
    }
}

/// Question tirée au hasard ; la réponse s'affiche au clic.
private struct QuestionContent: View {
    @Environment(WikiStore.self) private var store
    let entries: [SearchEntry]
    @State private var current: RevisionQuestion?
    @State private var showsAnswer = false

    var body: some View {
        let questions = RevisionQuestion.all(in: entries)
        VStack(alignment: .leading, spacing: 10) {
            if questions.isEmpty {
                EmptyHint("Aucune question. Ajoute-en avec /question dans une page.")
            } else if let current {
                Text(current.question)
                    .font(.body.weight(.medium))
                    .fixedSize(horizontal: false, vertical: true)
                if showsAnswer {
                    Text(current.answer)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.035)))
                        .textSelection(.enabled)
                }
                HStack(spacing: 10) {
                    Button(showsAnswer ? "Masquer" : "Voir la réponse") { showsAnswer.toggle() }
                    Button("Autre question") { pick(from: questions) }
                    Spacer()
                    Button(current.page.title) { store.openPage(current.page.url) }
                        .buttonStyle(.link)
                        .font(.caption)
                        .lineLimit(1)
                }
                .controlSize(.small)
            }
        }
        .onAppear { if current == nil { pick(from: questions) } }
        .onChange(of: questions.count) { if current == nil { pick(from: questions) } }
    }

    private func pick(from questions: [RevisionQuestion]) {
        showsAnswer = false
        let others = questions.filter { $0.question != current?.question }
        current = (others.isEmpty ? questions : others).randomElement()
    }
}

private struct SectionsChart: View {
    let sections: [DashboardStats.Section]

    var body: some View {
        if sections.isEmpty {
            EmptyHint("Aucune page pour l'instant.")
        } else {
            let maximum = sections.map(\.count).max() ?? 1
            VStack(alignment: .leading, spacing: 8) {
                ForEach(sections, id: \.name) { section in
                    HStack(spacing: 8) {
                        Text(section.name)
                            .font(.callout)
                            .lineLimit(1)
                            .frame(width: 150, alignment: .leading)
                        GeometryReader { geometry in
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.accentColor.opacity(0.7))
                                .frame(width: max(geometry.size.width * CGFloat(section.count) / CGFloat(maximum), 4))
                        }
                        .frame(height: 10)
                        Text("\(section.count)")
                            .font(.callout.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 28, alignment: .trailing)
                    }
                }
            }
        }
    }
}

// MARK: Réglages d'un widget

private struct WidgetSettingsView: View {
    @Environment(WikiStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var draft: DashboardWidget

    init(widget: DashboardWidget) {
        _draft = State(initialValue: widget)
    }

    private var usesFolder: Bool { [.folder, .tasks, .recent, .question].contains(draft.kind) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(draft.kind.label).font(.headline)

            TextField("Titre", text: $draft.title, prompt: Text(draft.kind.label))
                .textFieldStyle(.roundedBorder)

            if draft.kind == .countdown {
                DatePicker("Date", selection: Binding(
                    get: { draft.date ?? .now },
                    set: { draft.date = $0 }
                ), displayedComponents: .date)
            }

            if draft.kind == .note {
                TextEditor(text: $draft.text)
                    .font(.callout)
                    .frame(height: 120)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.primary.opacity(0.12)))
                Text("Mise en forme : **gras**, *italique*, `code`, [lien](https://…)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if usesFolder {
                Picker("Dossier", selection: $draft.folder) {
                    Text(draft.kind == .folder ? "Choisir…" : "Tout le wiki").tag("")
                    ForEach(store.dashboardFolderOptions, id: \.self) { option in
                        Text(option.label).tag(option.path)
                    }
                }
            }

            if draft.kind.hasLimit {
                Stepper("Éléments affichés : \(draft.limit)", value: $draft.limit, in: 3...30)
            }

            Toggle("Pleine largeur", isOn: $draft.wide)

            HStack {
                Spacer()
                Button("OK") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 320)
        // Enregistré à la fermeture (pas à chaque frappe).
        .onDisappear { store.updateWidget(draft) }
    }
}

// MARK: Calculs

struct DashboardStats {
    struct Section { let name: String; let count: Int }
    struct OpenTask: Identifiable {
        let id = UUID()
        let text: String
        let page: SearchEntry
    }

    let pageCount: Int
    let sections: [Section]
    let openTasks: [OpenTask]
    let questionCount: Int

    private static let taskPattern = try! NSRegularExpression( // swiftlint:disable:this force_try
        pattern: "^(?:>\\s*)*(?:[-*+]|\\d+\\.)\\s+\\[ \\]\\s+(\\S.*)$"
    )

    init(entries: [SearchEntry]) {
        pageCount = entries.count

        // Section = premier niveau du chemin (« Réseau › Nmap » -> « Réseau »).
        var counts: [String: Int] = [:]
        for entry in entries {
            let parts = entry.path.components(separatedBy: " › ")
            let section = parts.count > 1 ? parts[0] : "Racine"
            counts[section, default: 0] += 1
        }
        sections = counts.map { Section(name: $0.key, count: $0.value) }
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.name < $1.name }

        var tasks: [OpenTask] = []
        var questions = 0
        for entry in entries {
            for (index, line) in entry.lines.enumerated() where !entry.isCode[index] {
                let ns = line as NSString
                if let match = Self.taskPattern.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) {
                    tasks.append(OpenTask(text: ns.substring(with: match.range(at: 1)), page: entry))
                }
                let lower = line.lowercased()
                if lower.contains("[!reponse]") || lower.contains("[!réponse]") {
                    questions += 1
                }
            }
        }
        openTasks = tasks
        questionCount = questions
    }
}

// MARK: Composants

private struct StatTile: View {
    let value: Int
    let label: String
    let icon: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 0) {
                Text("\(value)")
                    .font(.title.weight(.semibold).monospacedDigit())
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.03)))
    }
}

/// Liste tronquée avec « … et N autres ».
private struct LimitedList<Content: View>: View {
    let total: Int
    let limit: Int
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            content
            if total > limit {
                Text("… et \(total - limit) autres")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct PageLink: View {
    let title: String
    let detail: String
    var icon = "doc.text"
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundStyle(.secondary)
                    .frame(width: 16)
                Text(title)
                    .lineLimit(1)
                Spacer(minLength: 8)
                if !detail.isEmpty {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct EmptyHint: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
    }
}
