import SwiftUI

/// Un élément du menu de complétion (commande « / » ou page « [[ »).
struct CompletionItem: Identifiable {
    let id: String
    let title: String
    let detail: String
    let icon: String
}

/// Une page proposée quand on tape « [[ ».
struct WikiLinkTarget {
    let title: String
    let path: String
}

/// Menu qui s'affiche sous le curseur quand on tape « / » ou « [[ » dans l'éditeur.
/// Flèches haut/bas pour choisir, Entrée ou Tab pour insérer, Échap pour fermer.
struct SlashMenuView: View {
    let items: [CompletionItem]
    let selectedIndex: Int
    let onSelect: (Int) -> Void

    static let rowHeight: CGFloat = 40
    static let width: CGFloat = 340
    static let margin: CGFloat = 8
    static let maxVisibleRows = 7

    /// Taille totale de la vue (marge pour l'ombre comprise).
    static func size(for count: Int) -> NSSize {
        let rows = CGFloat(min(count, maxVisibleRows))
        return NSSize(width: width + margin * 2, height: rows * rowHeight + 8 + margin * 2)
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        row(item, isSelected: index == selectedIndex)
                            .id(index)
                            .onTapGesture { onSelect(index) }
                    }
                }
                .padding(.vertical, 4)
            }
            .onChange(of: selectedIndex) { proxy.scrollTo(selectedIndex) }
        }
        .frame(
            width: Self.width,
            height: CGFloat(min(items.count, Self.maxVisibleRows)) * Self.rowHeight + 8
        )
        .background(Color(nsColor: .windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.12)))
        .shadow(color: .black.opacity(0.15), radius: 6, y: 2)
        .padding(Self.margin)
    }

    private func row(_ item: CompletionItem, isSelected: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: item.icon)
                .frame(width: 20)
                .foregroundStyle(isSelected ? Color.accentColor : .secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                Text(item.detail)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .frame(height: Self.rowHeight)
        .background(isSelected ? Color.accentColor.opacity(0.14) : Color.clear)
        .contentShape(Rectangle())
    }
}
