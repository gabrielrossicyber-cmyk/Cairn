import SwiftUI

/// Carte des liens de la page ouverte (Cmd+Maj+M).
///
///     Mentionnée dans  ──▶  [ PAGE ]  ──▶  Renvoie vers
///                              │
///                        Mêmes tags (#iam…)
///
/// Un clic sur une page recentre la carte sur elle ; « Lire la page » (Échap) revient au texte.
struct LinkMapView: View {
    @Environment(WikiStore.self) private var store

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if let url = store.openURL, let map = store.linkMap(for: url) {
                ScrollView([.vertical, .horizontal]) {
                    MapCanvas(map: map)
                        .padding(36)
                        .frame(maxWidth: .infinity)
                }
            } else {
                ContentUnavailableView("Page introuvable dans l'index", systemImage: "point.3.connected.trianglepath.dotted")
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    private var header: some View {
        HStack(spacing: 12) {
            Label("Carte des liens", systemImage: "point.3.connected.trianglepath.dotted")
                .font(.headline)
            Text("Clique sur une page pour centrer la carte sur elle.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Lire la page") { store.isLinkMapPresented = false }
                .keyboardShortcut(.cancelAction)
                .help("Revenir au texte (Échap)")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }
}

// MARK: Disposition

private struct MapCanvas: View {
    @Environment(WikiStore.self) private var store
    let map: LinkMap

    private static let columnWidth: CGFloat = 230
    private static let visibleLimit = 12

    var body: some View {
        VStack(spacing: 44) {
            HStack(alignment: .center, spacing: 72) {
                column(
                    title: "Mentionnée dans",
                    hint: "pages qui citent celle-ci",
                    empty: "Aucune page ne cite celle-ci. Écris [[\(map.center.title)]] dans une autre page.",
                    count: map.incoming.count
                ) {
                    ForEach(map.incoming.prefix(Self.visibleLimit)) { entry in
                        NodeCard(title: entry.title, detail: entry.path, icon: icon(entry)) {
                            store.openPage(entry.url)
                        }
                        .mapNode("in:" + entry.url.path)
                    }
                }

                CenterCard(entry: map.center)
                    .frame(width: 250)
                    .mapNode("center")

                column(
                    title: "Renvoie vers",
                    hint: "pages citées avec [[…]]",
                    empty: "Cette page ne cite aucune autre page. Tape [[ dans l'éditeur pour en lier une.",
                    count: map.outgoing.count
                ) {
                    ForEach(map.outgoing.prefix(Self.visibleLimit)) { target in
                        if let entry = target.entry {
                            NodeCard(title: entry.title, detail: entry.path, icon: icon(entry)) {
                                store.openPage(entry.url)
                            }
                            .mapNode("out:" + target.id)
                        } else {
                            NodeCard(title: target.name, detail: "Page à créer (clic)", icon: "plus.circle", isMissing: true) {
                                store.isLinkMapPresented = false
                                store.openWikiLink(target.name)
                            }
                            .mapNode("out:" + target.id)
                        }
                    }
                }
            }

            if !map.tagGroups.isEmpty {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Mêmes tags")
                        .font(.headline)
                    ForEach(map.tagGroups) { group in
                        VStack(alignment: .leading, spacing: 8) {
                            Button("#" + group.name) { store.openSearch(tag: group.key) }
                                .buttonStyle(.plain)
                                .font(.callout.weight(.semibold))
                                .foregroundStyle(Color.cairnMoss)
                                .padding(.horizontal, 9)
                                .padding(.vertical, 3)
                                .background(Capsule().fill(Color.cairnMoss.opacity(0.12)))
                                .help("Toutes les pages avec #\(group.name)")
                                .mapNode("tag:" + group.key)
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 190, maximum: 240), spacing: 10)],
                                      alignment: .leading, spacing: 10) {
                                ForEach(group.pages) { entry in
                                    NodeCard(title: entry.title, detail: entry.path, icon: icon(entry), compact: true) {
                                        store.openPage(entry.url)
                                    }
                                }
                            }
                            if group.hiddenCount > 0 {
                                Text("+ \(group.hiddenCount) autres pages")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .frame(maxWidth: Self.columnWidth * 2 + 250 + 144, alignment: .leading)
            }
        }
        // Les traits sont dessinés derrière les cartes, à partir de leurs positions.
        .backgroundPreferenceValue(MapNodeKey.self) { anchors in
            GeometryReader { proxy in
                let frames = anchors.mapValues { proxy[$0] }
                Canvas { context, _ in
                    draw(in: &context, frames: frames)
                }
            }
        }
    }

    @ViewBuilder
    private func column<Content: View>(title: String, hint: String, empty: String, count: Int,
                                       @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(count > 0 ? "\(title) (\(count))" : title).font(.headline)
                Text(hint).font(.caption).foregroundStyle(.secondary)
            }
            if count == 0 {
                Text(empty)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(Color.primary.opacity(0.12), style: StrokeStyle(lineWidth: 1, dash: [4, 4])))
            } else {
                content()
                if count > Self.visibleLimit {
                    Text("+ \(count - Self.visibleLimit) autres")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: Self.columnWidth)
    }

    private func icon(_ entry: SearchEntry) -> String {
        entry.isLocked ? "lock.doc" : "doc.text"
    }

    // MARK: Traits

    private func draw(in context: inout GraphicsContext, frames: [String: CGRect]) {
        guard let center = frames["center"] else { return }
        let line = Color.primary.opacity(0.28)

        // Pages qui citent -> page centrale
        for entry in map.incoming.prefix(Self.visibleLimit) {
            guard let from = frames["in:" + entry.url.path] else { continue }
            arrow(in: &context, from: CGPoint(x: from.maxX, y: from.midY),
                  to: CGPoint(x: center.minX, y: center.midY), color: line, dashed: false)
        }
        // Page centrale -> pages citées (pointillé si la page n'existe pas encore)
        for target in map.outgoing.prefix(Self.visibleLimit) {
            guard let to = frames["out:" + target.id] else { continue }
            arrow(in: &context, from: CGPoint(x: center.maxX, y: center.midY),
                  to: CGPoint(x: to.minX, y: to.midY), color: line, dashed: target.entry == nil)
        }
        // Page centrale -> tags (trait vert discret, sans flèche)
        for group in map.tagGroups {
            guard let chip = frames["tag:" + group.key] else { continue }
            var path = Path()
            let start = CGPoint(x: center.midX, y: center.maxY)
            let end = CGPoint(x: chip.midX, y: chip.minY)
            path.move(to: start)
            let dy = max(30, (end.y - start.y) * 0.5)
            path.addCurve(to: end, control1: CGPoint(x: start.x, y: start.y + dy), control2: CGPoint(x: end.x, y: end.y - dy))
            context.stroke(path, with: .color(Color.cairnMoss.opacity(0.45)), style: StrokeStyle(lineWidth: 1.2, dash: [3, 4]))
        }
    }

    /// Courbe horizontale avec une petite flèche à l'arrivée.
    private func arrow(in context: inout GraphicsContext, from start: CGPoint, to end: CGPoint, color: Color, dashed: Bool) {
        var path = Path()
        path.move(to: start)
        let dx = max(28, (end.x - start.x) * 0.5)
        path.addCurve(to: CGPoint(x: end.x - 6, y: end.y),
                      control1: CGPoint(x: start.x + dx, y: start.y),
                      control2: CGPoint(x: end.x - dx, y: end.y))
        context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 1.3, lineCap: .round, dash: dashed ? [4, 4] : []))

        var head = Path()
        head.move(to: end)
        head.addLine(to: CGPoint(x: end.x - 8, y: end.y - 4.5))
        head.addLine(to: CGPoint(x: end.x - 8, y: end.y + 4.5))
        head.closeSubpath()
        context.fill(head, with: .color(color))
    }
}

// MARK: Cartes

private struct CenterCard: View {
    let entry: SearchEntry

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: entry.isLocked ? "lock.doc.fill" : "doc.text.fill")
                .font(.title)
                .foregroundStyle(Color.cairnMoss)
            Text(entry.title)
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)
            if !entry.path.isEmpty {
                Text(entry.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            if !entry.tags.isEmpty {
                Text(entry.tags.prefix(4).map { "#" + $0 }.joined(separator: "  "))
                    .font(.caption)
                    .foregroundStyle(Color.cairnMoss)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.cairnMoss.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.cairnMoss.opacity(0.6), lineWidth: 1.5))
    }
}

private struct NodeCard: View {
    let title: String
    let detail: String
    let icon: String
    var isMissing = false
    var compact = false
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundStyle(isMissing ? Color.secondary : Color.cairnMoss)
                    .frame(width: 16)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(compact ? .callout : .body)
                        .lineLimit(1)
                    if !detail.isEmpty {
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.head)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, compact ? 6 : 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 9)
                .fill(isHovering ? Color.cairnMoss.opacity(0.10) : Color(nsColor: .controlBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 9)
                .strokeBorder(Color.primary.opacity(isMissing ? 0.25 : 0.12),
                              style: StrokeStyle(lineWidth: 1, dash: isMissing ? [4, 3] : [])))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help(isMissing ? "Cette page n'existe pas encore : clic pour la créer" : "Centrer la carte sur « \(title) »")
    }
}

// MARK: Positions des cartes (pour dessiner les traits)

private struct MapNodeKey: PreferenceKey {
    static var defaultValue: [String: Anchor<CGRect>] = [:]
    static func reduce(value: inout [String: Anchor<CGRect>], nextValue: () -> [String: Anchor<CGRect>]) {
        value.merge(nextValue()) { $1 }
    }
}

private extension View {
    func mapNode(_ id: String) -> some View {
        anchorPreference(key: MapNodeKey.self, value: .bounds) { [id: $0] }
    }
}
