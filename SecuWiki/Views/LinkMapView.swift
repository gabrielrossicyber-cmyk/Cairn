import SwiftUI

/// Carte des liens de la page ouverte (Cmd+Maj+M).
///
///     Mentionnée dans  ──▶  [ PAGE ]  ──▶  Renvoie vers
///                              ┆
///                         Mêmes tags
///
/// Un clic sur une page recentre la carte sur elle ; le fil en haut garde le parcours.
/// « Lire la page » (Échap) revient au texte.
struct LinkMapView: View {
    @Environment(WikiStore.self) private var store
    /// Pages visitées depuis l'ouverture de la carte (fil d'Ariane cliquable).
    @State private var trail: [URL] = []

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ZStack {
                DotGrid()
                if let url = store.openURL, let map = store.linkMap(for: url) {
                    ScrollView([.vertical, .horizontal]) {
                        MapCanvas(map: map)
                            .id(map.center.url)
                            .transition(.opacity.combined(with: .scale(scale: 0.985)))
                            .padding(.horizontal, 40)
                            .padding(.vertical, 36)
                            .frame(maxWidth: .infinity)
                    }
                    .animation(.easeOut(duration: 0.22), value: map.center.url)
                } else {
                    ContentUnavailableView("Page introuvable dans l'index", systemImage: "point.3.connected.trianglepath.dotted")
                }
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
        .onAppear { trail = store.openURL.map { [$0] } ?? [] }
        .onChange(of: store.openURL) { _, url in
            guard let url else { return }
            // Retour sur une page déjà dans le fil : on coupe après elle.
            if let index = trail.firstIndex(of: url) {
                trail = Array(trail.prefix(through: index))
            } else {
                trail = Array((trail + [url]).suffix(6))
            }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "point.3.connected.trianglepath.dotted")
                .foregroundStyle(Color.cairnMoss)
            Text("Carte des liens")
                .font(.headline)

            // Fil du parcours : IAM › Kerberos › Active Directory
            if trail.count > 1 {
                Divider().frame(height: 14)
                ForEach(Array(trail.enumerated()), id: \.element) { index, url in
                    if index > 0 {
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    let isLast = index == trail.count - 1
                    Button(title(for: url)) { store.openPage(url) }
                        .buttonStyle(.plain)
                        .font(.callout.weight(isLast ? .semibold : .regular))
                        .foregroundStyle(isLast ? Color.primary : Color.secondary)
                        .lineLimit(1)
                        .disabled(isLast)
                }
            } else {
                Text("Clique sur une page pour centrer la carte sur elle.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)
            Button {
                store.isLinkMapPresented = false
            } label: {
                Label("Lire la page", systemImage: "doc.text")
            }
            .keyboardShortcut(.cancelAction)
            .help("Revenir au texte (Échap)")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }

    private func title(for url: URL) -> String {
        let path = url.standardizedFileURL.path
        return store.searchIndex.first { $0.url.standardizedFileURL.path == path }?.title
            ?? url.deletingPathExtension().lastPathComponent
    }
}

// MARK: Disposition

private struct MapCanvas: View {
    @Environment(WikiStore.self) private var store
    let map: LinkMap
    /// Carte survolée : ses liens s'illuminent, les autres s'estompent.
    @State private var hovered: String?

    private static let columnWidth: CGFloat = 240
    private static let centerWidth: CGFloat = 270
    private static let gap: CGFloat = 84
    private static let visibleLimit = 12

    var body: some View {
        VStack(spacing: 52) {
            HStack(alignment: .center, spacing: Self.gap) {
                column(
                    title: "Mentionnée dans",
                    icon: "arrow.right.to.line",
                    hint: "Pages qui citent celle-ci",
                    empty: "Aucune page ne cite celle-ci.\nÉcris [[\(map.center.title)]] dans une autre page.",
                    count: map.incoming.count
                ) {
                    ForEach(map.incoming.prefix(Self.visibleLimit)) { entry in
                        NodeCard(id: "in:" + entry.url.path, title: entry.title, detail: entry.path,
                                 icon: icon(entry), hovered: $hovered) {
                            store.openPage(entry.url)
                        }
                    }
                }

                CenterCard(map: map, isHighlighted: hovered == "center")
                    .frame(width: Self.centerWidth)
                    .onHover { hovered = $0 ? "center" : (hovered == "center" ? nil : hovered) }
                    .mapNode("center")

                column(
                    title: "Renvoie vers",
                    icon: "arrow.right.from.line",
                    hint: "Pages citées avec [[…]]",
                    empty: "Cette page ne cite aucune autre page.\nTape [[ dans l'éditeur pour en lier une.",
                    count: map.outgoing.count
                ) {
                    ForEach(map.outgoing.prefix(Self.visibleLimit)) { target in
                        if let entry = target.entry {
                            NodeCard(id: "out:" + target.id, title: entry.title, detail: entry.path,
                                     icon: icon(entry), hovered: $hovered) {
                                store.openPage(entry.url)
                            }
                        } else {
                            NodeCard(id: "out:" + target.id, title: target.name, detail: "Page à créer",
                                     icon: "plus", isMissing: true, hovered: $hovered) {
                                store.isLinkMapPresented = false
                                store.openWikiLink(target.name)
                            }
                        }
                    }
                }
            }

            if !map.tagGroups.isEmpty {
                tagSection
            }
        }
        // Les traits sont dessinés derrière les cartes, à partir de leurs positions réelles.
        .backgroundPreferenceValue(MapNodeKey.self) { anchors in
            GeometryReader { proxy in
                let frames = anchors.mapValues { proxy[$0] }
                Canvas { context, _ in
                    draw(in: &context, frames: frames)
                }
            }
        }
        .animation(.easeOut(duration: 0.15), value: hovered)
    }

    // MARK: Colonnes

    @ViewBuilder
    private func column<Content: View>(title: String, icon: String, hint: String, empty: String, count: Int,
                                       @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(title: title, icon: icon, count: count)
            Text(hint)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.top, -6)

            if count == 0 {
                VStack(alignment: .leading, spacing: 6) {
                    Image(systemName: "link.badge.plus")
                        .foregroundStyle(.tertiary)
                    Text(empty)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.primary.opacity(0.12), style: StrokeStyle(lineWidth: 1, dash: [4, 4])))
            } else {
                content()
                if count > Self.visibleLimit {
                    Text("+ \(count - Self.visibleLimit) autres")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.leading, 4)
                }
            }
        }
        .frame(width: Self.columnWidth)
    }

    private var tagSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionTitle(title: "Mêmes tags", icon: "number", count: map.tagGroups.reduce(0) { $0 + $1.pages.count + $1.hiddenCount })
            ForEach(map.tagGroups) { group in
                VStack(alignment: .leading, spacing: 8) {
                    Button { store.openSearch(tag: group.key) } label: {
                        Text("#" + group.name)
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(Color.cairnMoss)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(Color.cairnMoss.opacity(0.12)))
                    }
                    .buttonStyle(.plain)
                    .help("Toutes les pages avec #\(group.name)")

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 200, maximum: 260), spacing: 10)],
                              alignment: .leading, spacing: 10) {
                        ForEach(group.pages) { entry in
                            NodeCard(id: "tag:\(group.key):" + entry.url.path, title: entry.title, detail: entry.path,
                                     icon: icon(entry), compact: true, isTracked: false, hovered: $hovered) {
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
        .padding(20)
        .frame(maxWidth: Self.columnWidth * 2 + Self.centerWidth + Self.gap * 2, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color.cairnMoss.opacity(0.04)))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.cairnMoss.opacity(0.18)))
        .mapNode("tags")
    }

    private func icon(_ entry: SearchEntry) -> String {
        entry.isLocked ? "lock.doc" : "doc.text"
    }

    // MARK: Traits

    private func draw(in context: inout GraphicsContext, frames: [String: CGRect]) {
        guard let center = frames["center"] else { return }

        func color(for node: String) -> (Color, CGFloat) {
            let active = hovered == node || hovered == "center"
            if active { return (Color.cairnMoss, 2) }
            return (Color.primary.opacity(hovered == nil ? 0.22 : 0.08), 1.3)
        }

        // Pages qui citent -> page centrale
        for entry in map.incoming.prefix(Self.visibleLimit) {
            let id = "in:" + entry.url.path
            guard let from = frames[id] else { continue }
            let (shade, width) = color(for: id)
            curve(in: &context, from: CGPoint(x: from.maxX, y: from.midY),
                  to: CGPoint(x: center.minX, y: center.midY), color: shade, width: width, dashed: false, arrow: true)
        }
        // Page centrale -> pages citées (pointillé : page à créer)
        for target in map.outgoing.prefix(Self.visibleLimit) {
            let id = "out:" + target.id
            guard let to = frames[id] else { continue }
            let (shade, width) = color(for: id)
            curve(in: &context, from: CGPoint(x: center.maxX, y: center.midY),
                  to: CGPoint(x: to.minX, y: to.midY), color: shade, width: width, dashed: target.entry == nil, arrow: true)
        }
        // Page centrale -> section des tags (vertical, pointillé vert)
        if let tags = frames["tags"] {
            var path = Path()
            let start = CGPoint(x: center.midX, y: center.maxY)
            let end = CGPoint(x: center.midX, y: tags.minY)
            path.move(to: start)
            path.addLine(to: end)
            context.stroke(path, with: .color(Color.cairnMoss.opacity(0.5)), style: StrokeStyle(lineWidth: 1.3, dash: [3, 4]))
            dot(in: &context, at: end, color: Color.cairnMoss.opacity(0.7))
        }

        // Points d'ancrage sur la page centrale
        let port = Color.cairnMoss
        if !map.incoming.isEmpty { dot(in: &context, at: CGPoint(x: center.minX, y: center.midY), color: port) }
        if !map.outgoing.isEmpty { dot(in: &context, at: CGPoint(x: center.maxX, y: center.midY), color: port) }
        if !map.tagGroups.isEmpty { dot(in: &context, at: CGPoint(x: center.midX, y: center.maxY), color: port) }
    }

    /// Courbe horizontale douce, avec une petite flèche à l'arrivée.
    private func curve(in context: inout GraphicsContext, from start: CGPoint, to end: CGPoint,
                       color: Color, width: CGFloat, dashed: Bool, arrow: Bool) {
        var path = Path()
        path.move(to: start)
        let tip = CGPoint(x: end.x - (arrow ? 7 : 0), y: end.y)
        let dx = max(30, (tip.x - start.x) * 0.55)
        path.addCurve(to: tip, control1: CGPoint(x: start.x + dx, y: start.y), control2: CGPoint(x: tip.x - dx, y: tip.y))
        context.stroke(path, with: .color(color),
                       style: StrokeStyle(lineWidth: width, lineCap: .round, dash: dashed ? [4, 4] : []))
        guard arrow else { return }
        var head = Path()
        head.move(to: end)
        head.addLine(to: CGPoint(x: end.x - 8, y: end.y - 4.5))
        head.addLine(to: CGPoint(x: end.x - 8, y: end.y + 4.5))
        head.closeSubpath()
        context.fill(head, with: .color(color))
    }

    private func dot(in context: inout GraphicsContext, at point: CGPoint, color: Color) {
        let rect = CGRect(x: point.x - 3.5, y: point.y - 3.5, width: 7, height: 7)
        context.fill(Path(ellipseIn: rect), with: .color(color))
    }
}

// MARK: Éléments

/// Titre de section : « MENTIONNÉE DANS   3 ».
private struct SectionTitle: View {
    let title: String
    let icon: String
    let count: Int

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption.weight(.semibold))
            Text(title.uppercased())
                .font(.caption.weight(.semibold))
                .tracking(0.6)
            Spacer(minLength: 4)
            if count > 0 {
                Text("\(count)")
                    .font(.caption2.weight(.semibold).monospacedDigit())
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.primary.opacity(0.07)))
            }
        }
        .foregroundStyle(.secondary)
    }
}

private struct CenterCard: View {
    let map: LinkMap
    let isHighlighted: Bool

    var body: some View {
        let entry = map.center
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(Color.cairnMoss.opacity(0.15))
                    .frame(width: 46, height: 46)
                Image(systemName: entry.isLocked ? "lock.doc.fill" : "doc.text.fill")
                    .font(.title3)
                    .foregroundStyle(Color.cairnMoss)
            }
            VStack(spacing: 3) {
                Text(entry.title)
                    .font(.title3.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                if !entry.path.isEmpty, entry.path != entry.title {
                    Text(entry.path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                }
            }
            if !entry.tags.isEmpty {
                HStack(spacing: 5) {
                    ForEach(entry.tags.prefix(3), id: \.self) { tag in
                        Text("#" + tag)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(Color.cairnMoss)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.cairnMoss.opacity(0.12)))
                    }
                }
            }
            Divider().padding(.horizontal, 10)
            HStack(spacing: 14) {
                stat(map.incoming.count, "citent")
                stat(map.outgoing.count, "cités")
                stat(map.tagGroups.reduce(0) { $0 + $1.pages.count + $1.hiddenCount }, "mêmes tags")
            }
        }
        .padding(.vertical, 20)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color(nsColor: .controlBackgroundColor))
                .shadow(color: Color.cairnMoss.opacity(isHighlighted ? 0.35 : 0.18), radius: isHighlighted ? 18 : 12, y: 4)
        )
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Color.cairnMoss.opacity(0.55), lineWidth: 1.5))
    }

    private func stat(_ value: Int, _ label: String) -> some View {
        VStack(spacing: 0) {
            Text("\(value)")
                .font(.headline.monospacedDigit())
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

private struct NodeCard: View {
    let id: String
    let title: String
    let detail: String
    let icon: String
    var isMissing = false
    var compact = false
    /// La carte a-t-elle un trait vers la page centrale (position à mémoriser) ?
    var isTracked = true
    @Binding var hovered: String?
    let action: () -> Void

    private var isHovering: Bool { hovered == id }

    var body: some View {
        let card = Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.callout)
                    .foregroundStyle(isMissing ? Color.secondary : Color.cairnMoss)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(compact ? .callout : .callout.weight(.medium))
                        .foregroundStyle(isMissing ? Color.secondary : Color.primary)
                        .lineLimit(1)
                    if !detail.isEmpty, detail != title {
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .truncationMode(.head)
                    }
                }
                Spacer(minLength: 0)
                if isHovering && !isMissing {
                    Image(systemName: "scope")
                        .font(.caption)
                        .foregroundStyle(Color.cairnMoss)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, compact ? 7 : 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isMissing ? Color.clear : Color(nsColor: .controlBackgroundColor))
                    .shadow(color: .black.opacity(isHovering ? 0.12 : 0.05), radius: isHovering ? 8 : 2, y: isHovering ? 3 : 1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(isHovering ? Color.cairnMoss.opacity(0.7) : Color.primary.opacity(isMissing ? 0.25 : 0.09),
                                  style: StrokeStyle(lineWidth: isHovering ? 1.4 : 1, dash: isMissing ? [4, 3] : []))
            )
            .scaleEffect(isHovering ? 1.015 : 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { inside in
            if inside { hovered = id } else if hovered == id { hovered = nil }
        }
        .help(isMissing ? "Cette page n'existe pas encore : clic pour la créer" : "Centrer la carte sur « \(title) »")

        if isTracked { card.mapNode(id) } else { card }
    }
}

/// Fond quadrillé de points, très discret : donne l'impression d'un plan de travail.
private struct DotGrid: View {
    var body: some View {
        Canvas { context, size in
            let spacing: CGFloat = 22
            let dot = Path(ellipseIn: CGRect(x: 0, y: 0, width: 1.6, height: 1.6))
            var y: CGFloat = spacing / 2
            while y < size.height {
                var x: CGFloat = spacing / 2
                while x < size.width {
                    context.fill(dot.offsetBy(dx: x, dy: y), with: .color(Color.primary.opacity(0.07)))
                    x += spacing
                }
                y += spacing
            }
        }
        .allowsHitTesting(false)
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
