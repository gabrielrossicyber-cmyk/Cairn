import SwiftUI
import Combine

/// Mode examen chronométré.
///
/// 1. Réglages : périmètre (dossier, tag), nombre de questions, durée.
/// 2. Examen : une question à la fois, tu écris ta réponse, tu affiches la correction
///    et tu te notes (juste / partiel / faux). À la fin du temps, l'examen s'arrête.
/// 3. Résultat : note sur 6 (barème suisse, réussi dès 4), détail, refaire les questions ratées.
///
/// Les questions viennent des blocs « /question » du wiki (question + encadré [!REPONSE]).
struct ExamView: View {
    @Environment(WikiStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    private enum Phase { case setup, running, results }

    private struct ExamItem: Identifiable {
        let id = UUID()
        let question: RevisionQuestion
        var answer = ""
        var revealed = false
        /// 1 = juste, 0,5 = partiel, 0 = faux ; nil = pas répondu (temps écoulé).
        var score: Double?
    }

    @State private var phase: Phase = .setup

    // Réglages
    @State private var folder = ""
    @State private var tag: String?
    @State private var count = 10
    @State private var minutes = 15

    // Examen en cours
    @State private var items: [ExamItem] = []
    @State private var index = 0
    @State private var startDate = Date.now
    @State private var endDate = Date.now
    @State private var duration: TimeInterval = 0
    @State private var scope = ""

    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        Group {
            switch phase {
            case .setup: setupView
            case .running: runningView
            case .results: resultsView
            }
        }
        .padding(24)
        .frame(minWidth: 720, idealWidth: 780, minHeight: 580, idealHeight: 640)
        .onReceive(ticker) { now in
            if phase == .running, now >= endDate { finish() }
        }
    }

    // MARK: 1. Réglages

    private var available: [RevisionQuestion] {
        RevisionQuestion.all(in: store.examEntries(folder: folder, tag: tag))
    }

    private var setupView: some View {
        let available = self.available
        let history = store.wikiSettings.examHistory

        return VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Label("Mode examen", systemImage: "timer")
                    .font(.title2.weight(.bold))
                Text("Questions tirées au hasard de tes blocs /question. Tu écris ta réponse, tu compares, tu te notes. Note sur 6 (barème suisse).")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Form {
                Picker("Dossier", selection: $folder) {
                    Text("Tout le wiki").tag("")
                    ForEach(store.dashboardFolderOptions, id: \.self) { option in
                        Text(option.label).tag(option.path)
                    }
                }
                Picker("Tag", selection: $tag) {
                    Text("Tous").tag(String?.none)
                    ForEach(store.tagIndex) { info in
                        Text("#\(info.name)  (\(info.count))").tag(String?.some(info.key))
                    }
                }
                Stepper(value: $count, in: 1...max(available.count, 1)) {
                    Text("Questions : \(min(count, max(available.count, 1)))  ·  \(available.count) disponibles")
                }
                .disabled(available.isEmpty)
                Stepper(value: $minutes, in: 1...240) {
                    Text("Durée : \(minutes) min")
                }
            }
            .formStyle(.grouped)
            .frame(maxHeight: 230)

            if available.isEmpty {
                Label("Aucune question dans ce périmètre. Ajoute des questions avec /question dans tes pages : la question sur une ligne, la réponse dans l'encadré juste en dessous.",
                      systemImage: "exclamationmark.bubble")
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !history.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Derniers examens").font(.headline)
                    ForEach(history.prefix(5)) { result in
                        HStack {
                            Text(ExamGrading.format(result.grade))
                                .font(.body.weight(.semibold).monospacedDigit())
                                .foregroundStyle(result.grade >= ExamGrading.passingGrade ? Color.green : Color.red)
                                .frame(width: 34, alignment: .leading)
                            Text(result.scope).lineLimit(1)
                            Spacer()
                            Text("\(Self.points(result.points)) / \(result.total)")
                                .foregroundStyle(.secondary)
                            Text(result.date.formatted(.dateTime.day().month(.abbreviated).hour().minute().locale(Locale(identifier: "fr_CH"))))
                                .foregroundStyle(.tertiary)
                                .frame(width: 130, alignment: .trailing)
                        }
                        .font(.callout)
                    }
                }
            }

            Spacer(minLength: 0)

            HStack {
                Button("Annuler") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Commencer l'examen") { start(with: available.shuffled(), count: count) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(available.isEmpty)
            }
        }
        .onAppear {
            count = min(count, max(available.count, 1))
        }
    }

    private func start(with questions: [RevisionQuestion], count: Int, minutes override: Int? = nil) {
        let chosen = questions.prefix(max(1, min(count, questions.count)))
        items = chosen.map { ExamItem(question: $0) }
        index = 0
        startDate = .now
        endDate = .now.addingTimeInterval(TimeInterval((override ?? minutes) * 60))
        scope = store.examScopeLabel(folder: folder, tag: tag)
        phase = .running
    }

    // MARK: 2. Examen

    private var runningView: some View {
        let item = items[index]

        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                Text("Question \(index + 1) / \(items.count)")
                    .font(.headline)
                Spacer()
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let remaining = max(0, endDate.timeIntervalSince(context.date))
                    Label(Self.clock(remaining), systemImage: "timer")
                        .font(.title3.monospacedDigit().weight(.semibold))
                        .foregroundStyle(remaining < 60 ? Color.red : Color.primary)
                }
                Button("Terminer") { finish() }
                    .help("Terminer maintenant : les questions restantes comptent 0")
            }
            ProgressView(value: Double(index), total: Double(max(items.count, 1)))

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(Self.markdown(item.question.question))
                        .font(.title3.weight(.medium))
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    ZStack(alignment: .topLeading) {
                        TextEditor(text: $items[index].answer)
                            .font(.body)
                            .scrollContentBackground(.hidden)
                            .padding(6)
                            .frame(minHeight: 130)
                            .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.04)))
                        if item.answer.isEmpty {
                            Text("Ta réponse… (l'écrire t'oblige à la retrouver de mémoire)")
                                .foregroundStyle(.tertiary)
                                .padding(.horizontal, 11)
                                .padding(.vertical, 6)
                                .allowsHitTesting(false)
                        }
                    }

                    if item.revealed {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Réponse attendue").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                            Text(Self.markdown(item.question.answer))
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                            Text("Source : \(item.question.page.title)")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.accentColor.opacity(0.08)))
                    }
                }
            }

            HStack(spacing: 10) {
                if item.revealed {
                    Text("Comment as-tu répondu ?").foregroundStyle(.secondary)
                    Spacer()
                    Button("Faux") { grade(0) }
                        .keyboardShortcut("1", modifiers: .command)
                        .help("Cmd+1")
                    Button("Partiel") { grade(0.5) }
                        .keyboardShortcut("2", modifiers: .command)
                        .help("Cmd+2")
                    Button("Juste") { grade(1) }
                        .keyboardShortcut("3", modifiers: .command)
                        .buttonStyle(.borderedProminent)
                        .help("Cmd+3")
                } else {
                    Button("Passer") { grade(0) }
                        .help("Compte 0 point")
                    Spacer()
                    Button("Voir la réponse") { items[index].revealed = true }
                        .keyboardShortcut(.return, modifiers: .command)
                        .buttonStyle(.borderedProminent)
                        .help("Cmd+Entrée")
                }
            }
        }
    }

    private func grade(_ score: Double) {
        items[index].score = score
        items[index].revealed = true
        if index + 1 < items.count {
            index += 1
        } else {
            finish()
        }
    }

    private func finish() {
        guard phase == .running else { return }
        duration = Date.now.timeIntervalSince(startDate)
        phase = .results
        store.recordExam(ExamResult(
            date: .now,
            scope: scope,
            points: totalPoints,
            total: items.count,
            durationSeconds: Int(duration)
        ))
    }

    // MARK: 3. Résultat

    private var totalPoints: Double { items.reduce(0) { $0 + ($1.score ?? 0) } }

    private var resultsView: some View {
        let grade = ExamGrading.swissGrade(points: totalPoints, total: items.count)
        let passed = grade >= ExamGrading.passingGrade
        let failed = items.filter { ($0.score ?? 0) < 1 }

        return VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 18) {
                Text(ExamGrading.format(grade))
                    .font(.system(size: 56, weight: .bold, design: .rounded))
                    .foregroundStyle(passed ? Color.green : Color.red)
                VStack(alignment: .leading, spacing: 4) {
                    Text(passed ? "Réussi" : "Insuffisant")
                        .font(.title2.weight(.bold))
                    Text("\(Self.points(totalPoints)) / \(items.count) points  ·  \(Self.clock(duration))  ·  \(scope)")
                        .foregroundStyle(.secondary)
                }
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(items) { item in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: Self.icon(for: item.score))
                                .foregroundStyle(Self.color(for: item.score))
                                .font(.title3)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(Self.markdown(item.question.question))
                                    .font(.body.weight(.medium))
                                    .fixedSize(horizontal: false, vertical: true)
                                if !item.answer.isEmpty {
                                    Text("Toi : \(item.answer)")
                                        .font(.callout)
                                        .foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                if (item.score ?? 0) < 1 {
                                    Text(Self.markdown(item.question.answer))
                                        .font(.callout)
                                        .padding(8)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .background(RoundedRectangle(cornerRadius: 6).fill(Color.accentColor.opacity(0.07)))
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                Button("Revoir : \(item.question.page.title)") {
                                    store.openPage(item.question.page.url)
                                    dismiss()
                                }
                                .buttonStyle(.link)
                                .font(.caption)
                            }
                        }
                        Divider()
                    }
                }
            }

            HStack {
                Button("Fermer") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Nouvel examen") { phase = .setup }
                Button("Refaire les \(failed.count) questions ratées") {
                    let share = Double(failed.count) / Double(max(items.count, 1))
                    start(with: failed.map(\.question).shuffled(), count: failed.count,
                          minutes: max(1, Int((Double(minutes) * share).rounded(.up))))
                    scope += " (ratées)"
                }
                .keyboardShortcut(.defaultAction)
                .disabled(failed.isEmpty)
            }
        }
    }

    // MARK: Outils

    private static func clock(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded(.down))
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    private static func points(_ value: Double) -> String {
        value.truncatingRemainder(dividingBy: 1) == 0 ? String(format: "%.0f", value) : String(format: "%.1f", value)
    }

    private static func markdown(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(text)
    }

    private static func icon(for score: Double?) -> String {
        switch score {
        case 1?: "checkmark.circle.fill"
        case 0.5?: "circle.lefthalf.filled"
        case 0?: "xmark.circle.fill"
        default: "clock.badge.xmark"
        }
    }

    private static func color(for score: Double?) -> Color {
        switch score {
        case 1?: .green
        case 0.5?: .orange
        default: .red
        }
    }
}
