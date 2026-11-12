import SwiftUI

/// Sommaire de la page ouverte (panneau de droite) : clic sur un titre = on y va.
struct OutlinePanel: View {
    @Environment(WikiStore.self) private var store

    var body: some View {
        let headings = MarkdownPage.headings(in: store.rawText)

        Group {
            if store.openURL == nil || headings.isEmpty {
                ContentUnavailableView(
                    "Pas de titres",
                    systemImage: "list.bullet.indent",
                    description: Text("Les titres # de la page apparaîtront ici.")
                )
            } else {
                List(headings) { heading in
                    Button { store.scrollTo(heading) } label: {
                        Text(heading.title)
                            .font(.system(size: 12, weight: heading.level <= 2 ? .semibold : .regular))
                            .foregroundStyle(heading.level <= 2 ? Color.primary : Color.secondary)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.leading, CGFloat(max(heading.level - 1, 0)) * 12)
                }
                .listStyle(.sidebar)
            }
        }
        .inspectorColumnWidth(min: 160, ideal: 220, max: 320)
    }
}
