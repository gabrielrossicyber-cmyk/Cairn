import Foundation

/// Ce que les vues tirent du texte de la page ouverte (en-tête, tags, variables…).
struct PageAnalysis {
    let page: MarkdownPage
    let tags: [String]
    /// Variables utilisées dans le texte sans être déclarées dans l'en-tête.
    let undeclaredVariables: [String]
    /// Lignes de l'en-tête YAML (absentes de l'aperçu, pour le défilement synchronisé).
    let headerLines: Int
}

/// Cache de l'analyse : le texte n'est relu qu'une fois par frappe, au lieu d'une fois par vue
/// (page, bandeau des tags, barre des variables, défilement synchronisé).
final class PageAnalysisCache {
    private var text: String?
    private var value: PageAnalysis?

    func analysis(of text: String) -> PageAnalysis {
        if let value, let cached = self.text, cached == text { return value }
        let page = MarkdownPage.parse(text)
        let declared = Set(page.variables.map(\.name))
        let value = PageAnalysis(
            page: page,
            tags: MarkdownPage.tags(in: text),
            undeclaredVariables: MarkdownPage.usedVariableNames(in: page.body).filter { !declared.contains($0) },
            headerLines: MarkdownPage.headerLineCount(text, body: page.body)
        )
        self.text = text
        self.value = value
        return value
    }
}

extension WikiStore {
    /// Analyse de la page ouverte. Lire cette propriété dans une vue l'abonne au texte de la page.
    var openPageAnalysis: PageAnalysis {
        pageAnalysisCache.analysis(of: rawText)
    }
}
