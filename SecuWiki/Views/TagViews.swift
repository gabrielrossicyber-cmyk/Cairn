import SwiftUI

/// Tags dans la barre latérale : les plus utilisés en pastilles compactes (plusieurs par ligne),
/// et un bouton « Tous les tags » qui ouvre un panneau avec filtre et tri.
struct SidebarTagCloud: View {
    @Environment(WikiStore.self) private var store
    @State private var isBrowserPresented = false

    /// Nombre de pastilles visibles avant « Tous les tags ».
    private static let visibleCount = 12

    var body: some View {
        let popular = store.tagIndex
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            .prefix(Self.visibleCount)

        VStack(alignment: .leading, spacing: 8) {
            FlowLayout(spacing: 5) {
                ForEach(popular) { tag in
                    TagChip(tag: tag) { store.openSearch(tag: tag.key) }
                }
            }
            Button {
                isBrowserPresented = true
            } label: {
                Label(store.tagIndex.count > Self.visibleCount
                      ? "Tous les tags (\(store.tagIndex.count))"
                      : "Parcourir les tags", systemImage: "line.3.horizontal.decrease.circle")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .popover(isPresented: $isBrowserPresented, arrowEdge: .trailing) {
                TagBrowser { tag in
                    isBrowserPresented = false
                    store.openSearch(tag: tag.key)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

/// Une pastille de tag : « #iam 3 ». Les noms longs sont coupés (nom complet au survol).
struct TagChip: View {
    let tag: TagInfo
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text("#" + tag.name)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text("\(tag.count)")
                    .font(.system(size: 9, weight: .semibold).monospacedDigit())
                    .opacity(0.65)
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(Color.cairnMoss)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .frame(maxWidth: 165, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .background(Capsule().fill(Color.cairnMoss.opacity(isHovering ? 0.22 : 0.11)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help("#\(tag.name) : \(tag.count) page\(tag.count > 1 ? "s" : "")")
    }
}

/// Panneau « Tous les tags » : filtre au clavier, tri par nom ou par nombre de pages.
struct TagBrowser: View {
    @Environment(WikiStore.self) private var store
    let onSelect: (TagInfo) -> Void

    private enum Sort: String, CaseIterable { case usage = "Les plus utilisés", name = "A → Z" }

    @State private var filter = ""
    @State private var sort: Sort = .usage
    @FocusState private var isFilterFocused: Bool

    private var tags: [TagInfo] {
        let key = SearchEngine.normalize(filter.trimmingCharacters(in: .whitespaces))
        let filtered = key.isEmpty ? store.tagIndex : store.tagIndex.filter {
            $0.key.contains(key)
        }
        switch sort {
        case .usage:
            return filtered.sorted { $0.count != $1.count ? $0.count > $1.count : $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        case .name:
            return filtered.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Filtrer les tags", text: $filter)
                    .textFieldStyle(.plain)
                    .focused($isFilterFocused)
                    .onSubmit { if let first = tags.first { onSelect(first) } }
            }
            .padding(7)
            .background(RoundedRectangle(cornerRadius: 7).fill(Color.primary.opacity(0.05)))

            Picker("", selection: $sort) {
                ForEach(Sort.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if tags.isEmpty {
                Text("Aucun tag ne contient « \(filter) ».")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 80)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(tags) { tag in
                            TagBrowserRow(tag: tag) { onSelect(tag) }
                        }
                    }
                }
                .frame(maxHeight: 360)
            }

            Text("\(store.tagIndex.count) tags · ↩ ouvre le premier")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(12)
        .frame(width: 300)
        .onAppear { isFilterFocused = true }
    }
}

private struct TagBrowserRow: View {
    let tag: TagInfo
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text("#" + tag.name)
                    .foregroundStyle(Color.cairnMoss)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text("\(tag.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 6).fill(isHovering ? Color.cairnMoss.opacity(0.12) : Color.clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}

/// Disposition « en ligne » qui passe à la ligne quand la place manque (nuage de pastilles).
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var widest: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            let width = min(size.width, maxWidth)
            if x > 0, x + width > maxWidth {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += width + spacing
            rowHeight = max(rowHeight, size.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: proposal.width ?? widest, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            let width = min(size.width, bounds.width)
            if x > bounds.minX, x + width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(width: width, height: size.height))
            x += width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
