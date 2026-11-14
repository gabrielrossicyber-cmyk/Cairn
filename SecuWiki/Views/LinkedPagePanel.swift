import SwiftUI

/// Panneau de droite : aperçu de la page ouverte via un lien [[…]], sans quitter la page actuelle.
/// « Ouvrir » la remplace dans la vue principale, « × » ferme le panneau.
struct LinkedPagePanel: View {
    @Environment(WikiStore.self) private var store
    let url: URL
    @State private var text = ""
    private var prefs = PreviewPrefs()

    init(url: URL) {
        self.url = url
    }

    var body: some View {
        let page = MarkdownPage.parse(text)

        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "link")
                    .foregroundStyle(.secondary)
                Text(title(page))
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 4)
                Button("Ouvrir") {
                    store.openPage(url)
                    store.peekURL = nil
                }
                .controlSize(.small)
                .help("Afficher cette page à la place de la page actuelle")
                Button {
                    store.peekURL = nil
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.borderless)
                .help("Fermer le panneau")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            MarkdownWebView(
                markdown: MarkdownPage.substitute(page.body, variables: store.effectiveVariables(page)),
                pageID: url,
                context: {
                    var context = prefs.context(base: url.deletingLastPathComponent().path, pages: store.pageKeys)
                    context.secretNames = store.secretNames
                    return context
                }(),
                onWikiLink: { store.openWikiLink($0) }
            )
        }
        .background(Color(nsColor: .textBackgroundColor))
        // Relit la page liée quand elle change (ou quand elle est enregistrée).
        .task(id: "\(url.path)#\(store.searchIndex.count)#\(store.savedText.count)#\(store.lockSessions.count)") {
            let raw = (try? String(contentsOf: url, encoding: .utf8)) ?? "Impossible de lire cette page."
            if PageCrypto.isLocked(raw) {
                // Page chiffrée : lisible ici seulement si elle a déjà été déverrouillée.
                let session = store.lockSessions[WikiStore.lockKey(url)]
                text = session.flatMap { try? PageCrypto.open(raw, session: $0) }
                    ?? "> [!INFORMATION]\n> Page verrouillée. Clique sur « Ouvrir » pour la déverrouiller.\n"
            } else {
                text = raw
            }
        }
    }

    private func title(_ page: MarkdownPage) -> String {
        if let title = page.frontMatter["title"], !title.isEmpty { return title }
        let name = url.lastPathComponent.lowercased() == "index.md"
            ? url.deletingLastPathComponent().lastPathComponent
            : url.deletingPathExtension().lastPathComponent
        return WikiScanner.displayName(name)
    }
}
