import PBIPKit
import SwiftUI

// MARK: - Diagramme du modèle

/// Tables et relations dessinées ; le détail d'une relation s'affiche en passant la souris dessus.
struct ModelDiagramView: View {
    let semantic: SemanticModel
    @State private var layout = ModelDiagram.Layout.grid
    @State private var zoom = 1.0

    var body: some View {
        let diagram = ModelDiagram.make(semantic, layout: layout)
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Text("Modèle").font(.title).bold()
                Text("\(semantic.tables.count) tables · \(semantic.relationships.count) relations")
                    .foregroundStyle(.secondary)
                Spacer()
                Picker("Disposition", selection: $layout) {
                    Label("Ranger", systemImage: "square.grid.2x2").tag(ModelDiagram.Layout.grid)
                    Label("Étoile / flocon", systemImage: "asterisk").tag(ModelDiagram.Layout.star)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .help("Ranger : faits en haut, dimensions à gauche. Étoile / flocon : chaque table de faits entourée de ses dimensions.")
                ZoomControls(zoom: $zoom)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 8)
            DiagramLegend()
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
            Divider()
            // Le diagramme part du coin supérieur gauche, même s'il est plus petit que la zone.
            GeometryReader { geo in
                ScrollView([.horizontal, .vertical]) {
                    DiagramCanvas(diagram: diagram, relationships: semantic.relationships, zoom: zoom)
                        .frame(width: diagram.width, height: diagram.height, alignment: .topLeading)
                        .scaleEffect(zoom, anchor: .topLeading)
                        .frame(width: diagram.width * zoom, height: diagram.height * zoom, alignment: .topLeading)
                        .frame(minWidth: geo.size.width, minHeight: geo.size.height, alignment: .topLeading)
                }
            }
            .background(Color(nsColor: .textBackgroundColor))
        }
    }
}

struct ZoomControls: View {
    @Binding var zoom: Double

    var body: some View {
        HStack(spacing: 4) {
            Button { zoom = max(0.25, zoom - 0.25) } label: { Image(systemName: "minus.magnifyingglass") }
                .help("Zoom arrière")
            Button { zoom = 1 } label: { Text("\(Int((zoom * 100).rounded())) %").monospacedDigit().frame(minWidth: 44) }
                .help("Taille réelle")
            Button { zoom = min(2, zoom + 0.25) } label: { Image(systemName: "plus.magnifyingglass") }
                .help("Zoom avant")
        }
        .buttonStyle(.borderless)
    }
}

struct DiagramLegend: View {
    var body: some View {
        HStack(spacing: 14) {
            ForEach([ModelDiagram.Role.fact, .dimension, .isolated], id: \.self) { role in
                HStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 2).fill(role.color).frame(width: 10, height: 10)
                    Text(role.label)
                }
            }
            Text("Survolez un lien pour le détail de la relation · double-clic sur une table pour l'ouvrir")
                .foregroundStyle(.tertiary)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}

extension ModelDiagram.Role {
    var color: Color {
        switch self {
        case .fact: return .blue
        case .dimension: return .green
        case .isolated: return .gray
        }
    }

    var label: String {
        switch self {
        case .fact: return "Table de faits"
        case .dimension: return "Dimension"
        case .isolated: return "Sans relation"
        }
    }
}

/// Géométrie d'un lien tracé : ligne brisée, du côté `from` au côté `to`.
extension ModelDiagram.Edge {
    var cgPoints: [CGPoint] { points.map { CGPoint(x: $0.x, y: $0.y) } }

    var length: Double {
        zip(cgPoints, cgPoints.dropFirst()).reduce(0) { $0 + hypot($1.1.x - $1.0.x, $1.1.y - $1.0.y) }
    }

    func distance(to p: CGPoint) -> Double {
        zip(cgPoints, cgPoints.dropFirst()).map { a, b in
            let dx = b.x - a.x, dy = b.y - a.y
            let len2 = dx * dx + dy * dy
            let t = len2 == 0 ? 0 : max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / len2))
            return hypot(p.x - (a.x + t * dx), p.y - (a.y + t * dy))
        }.min() ?? .infinity
    }

    /// Point situé à la distance `d` du début, et direction unitaire du segment à cet endroit.
    func point(atDistance d: Double) -> (point: CGPoint, ux: Double, uy: Double) {
        var rest = max(0, d)
        let pts = cgPoints
        for (a, b) in zip(pts, pts.dropFirst()) {
            let len = hypot(b.x - a.x, b.y - a.y)
            guard len > 0 else { continue }
            if rest <= len || b == pts.last {
                let t = min(rest / len, 1)
                return (CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t), (b.x - a.x) / len, (b.y - a.y) / len)
            }
            rest -= len
        }
        return (pts.first ?? .zero, 1, 0)
    }
}

struct DiagramCanvas: View {
    @EnvironmentObject var model: AppModel
    let diagram: ModelDiagram
    let relationships: [Relationship]
    let zoom: Double
    @State private var hovered: Int?
    @State private var pointer = CGPoint.zero

    var body: some View {
        let edges = diagram.edges
        let highlighted = hovered.map { [relationships[edges[$0].relationship].from, relationships[edges[$0].relationship].to] } ?? []
        ZStack(alignment: .topLeading) {
            Canvas { context, _ in
                for (i, edge) in edges.enumerated() where i != hovered {
                    draw(edge, highlighted: false, in: &context)
                }
                // Le lien survolé par-dessus les autres.
                if let i = hovered, i < edges.count { draw(edges[i], highlighted: true, in: &context) }
            }
            ForEach(diagram.nodes, id: \.table) { node in
                TableBox(node: node, highlighted: highlighted)
                    .frame(width: node.width, height: node.height)
                    .offset(x: node.x, y: node.y)
                    .onTapGesture(count: 2) { model.selection = .table(node.table) }
            }
            if let i = hovered, i < edges.count {
                RelationshipCard(relationship: relationships[edges[i].relationship])
                    .fixedSize()
                    .scaleEffect(1 / zoom, anchor: .topLeading)
                    .offset(x: pointer.x + 14, y: pointer.y + 14)
                    .allowsHitTesting(false)
            }
        }
        .contentShape(Rectangle())
        .onContinuousHover { phase in
            switch phase {
            case .active(let p):
                pointer = p
                let nearest = edges.indices.min { edges[$0].distance(to: p) < edges[$1].distance(to: p) }
                hovered = nearest.flatMap { edges[$0].distance(to: p) <= 7 / zoom ? $0 : nil }
            case .ended:
                hovered = nil
            }
        }
    }

    func draw(_ edge: ModelDiagram.Edge, highlighted: Bool, in context: inout GraphicsContext) {
        let r = relationships[edge.relationship]
        let color: Color = highlighted ? .accentColor : .secondary
        var line = Path()
        line.addLines(edge.cgPoints)
        context.stroke(line, with: .color(color.opacity(highlighted ? 1 : 0.7)),
                       style: StrokeStyle(lineWidth: highlighted ? 2.5 : 1.2, lineJoin: .round, dash: r.isActive ? [] : [6, 4]))

        // Cardinalité près de chaque bout, décalée sur le côté de la ligne.
        let length = edge.length
        let near = min(length / 2, 14)
        for (d, cardinality) in [(near, r.fromCardinality), (length - near, r.toCardinality)] {
            let (p, ux, uy) = edge.point(atDistance: d)
            context.draw(Text(cardinality == "one" ? "1" : "*").font(.caption.bold()).foregroundColor(color),
                         at: CGPoint(x: p.x - uy * 9, y: p.y + ux * 9))
        }

        // Sens du filtrage au milieu : du côté « un » (to) vers le côté « plusieurs » (from).
        let both = r.crossFilteringBehavior == "bothDirections"
        arrow(edge, at: length / 2 - (both ? 7 : 0), towardStart: true, color: color, in: &context)
        if both { arrow(edge, at: length / 2 + 7, towardStart: false, color: color, in: &context) }
    }

    func arrow(_ edge: ModelDiagram.Edge, at d: Double, towardStart: Bool, color: Color, in context: inout GraphicsContext) {
        var (tip, ux, uy) = edge.point(atDistance: d)
        if towardStart { ux = -ux; uy = -uy }
        var head = Path()
        head.move(to: CGPoint(x: tip.x + ux * 5, y: tip.y + uy * 5))
        head.addLine(to: CGPoint(x: tip.x - ux * 5 - uy * 5, y: tip.y - uy * 5 + ux * 5))
        head.addLine(to: CGPoint(x: tip.x - ux * 5 + uy * 5, y: tip.y - uy * 5 - ux * 5))
        head.closeSubpath()
        context.fill(head, with: .color(color))
    }
}

struct TableBox: View {
    let node: ModelDiagram.Node
    /// Colonnes de la relation survolée, mises en évidence.
    let highlighted: [ColumnRef]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(node.table)
                .font(.callout.bold())
                .lineLimit(1)
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity, minHeight: ModelDiagram.headerHeight, alignment: .leading)
                .background(node.role.color.opacity(0.85))
            ForEach(node.rows, id: \.self) { row in
                let on = isHighlighted(row)
                Text(row)
                    .font(.caption)
                    .fontWeight(on ? .bold : .regular)
                    .foregroundStyle(on ? Color.accentColor : .primary)
                    .lineLimit(1)
                    .padding(.horizontal, 8)
                    .frame(maxWidth: .infinity, minHeight: ModelDiagram.rowHeight, alignment: .leading)
                    .background(on ? Color.accentColor.opacity(0.12) : .clear)
            }
            if let footer {
                Text(footer)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .frame(maxWidth: .infinity, minHeight: ModelDiagram.rowHeight, alignment: .leading)
            }
            Spacer(minLength: 0)
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(node.role.color.opacity(0.6)))
        .shadow(color: .black.opacity(0.08), radius: 2, y: 1)
        .help(node.table)
    }

    var footer: String? {
        var parts: [String] = []
        if node.hiddenRowCount > 0 { parts.append("+\(node.hiddenRowCount) colonnes") }
        if node.measureCount > 0 { parts.append("\(node.measureCount) mesure\(node.measureCount > 1 ? "s" : "")") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    func isHighlighted(_ column: String) -> Bool {
        highlighted.contains {
            $0.table.caseInsensitiveCompare(node.table) == .orderedSame && $0.column.caseInsensitiveCompare(column) == .orderedSame
        }
    }
}

struct RelationshipCard: View {
    let relationship: Relationship

    var body: some View {
        let r = relationship
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(r.from.displayName).bold()
                Text(symbol(r.fromCardinality)).foregroundStyle(.secondary)
                Image(systemName: "arrow.right").foregroundStyle(.secondary)
                Text(symbol(r.toCardinality)).foregroundStyle(.secondary)
                Text(r.to.displayName).bold()
            }
            Text("Cardinalité : \(cardinality(r))")
            Text("Filtrage : \(r.crossFilteringBehavior == "bothDirections" ? "dans les deux sens" : "de \(r.to.table) vers \(r.from.table)")")
            if !r.isActive {
                Text("Relation inactive").foregroundStyle(.orange)
            }
        }
        .font(.callout)
        .padding(10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(nsColor: .separatorColor)))
        .shadow(radius: 4)
    }

    func symbol(_ c: String) -> String { c == "one" ? "1" : "*" }

    func cardinality(_ r: Relationship) -> String {
        func word(_ c: String) -> String { c == "one" ? "un" : "plusieurs" }
        return "\(word(r.fromCardinality)) à \(word(r.toCardinality)) (\(r.cardinality))"
    }
}

// MARK: - Toutes les mesures

/// Ordre « tout déplier / tout replier » envoyé aux dossiers et aux mesures d'une liste.
/// `token` change à chaque clic, pour que le même ordre puisse être redonné.
struct ExpansionCommand: Equatable {
    var expanded: Bool
    var token: Int
}

private struct ExpansionCommandKey: EnvironmentKey {
    static let defaultValue: ExpansionCommand? = nil
}

extension EnvironmentValues {
    var expansionCommand: ExpansionCommand? {
        get { self[ExpansionCommandKey.self] }
        set { self[ExpansionCommandKey.self] = newValue }
    }
}

/// Mesures de toutes les tables, rangées par table puis par dossier d'affichage.
struct AllMeasuresView: View {
    @EnvironmentObject var model: AppModel
    let semantic: SemanticModel
    @State private var search = ""
    @State private var command: ExpansionCommand?

    func expandAll(_ expanded: Bool) {
        command = ExpansionCommand(expanded: expanded, token: (command?.token ?? 0) + 1)
    }

    func matching(_ table: PBIPKit.Table) -> [Measure] {
        let q = search.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return table.measures }
        return table.measures.filter { $0.name.localizedCaseInsensitiveContains(q) || $0.expression.localizedCaseInsensitiveContains(q) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Mesures").font(.title).bold()
                    Text("\(semantic.measureCount)").foregroundStyle(.secondary)
                    Spacer()
                    Button { expandAll(true) } label: { Label("Tout déplier", systemImage: "chevron.down.circle") }
                        .help("Déplier tous les dossiers et afficher le DAX de toutes les mesures")
                    Button { expandAll(false) } label: { Label("Tout replier", systemImage: "chevron.right.circle") }
                        .help("Replier tous les dossiers et toutes les mesures")
                    TextField("Rechercher (nom ou DAX)", text: $search)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 260)
                }
                let tables = semantic.tables.map { ($0, matching($0)) }.filter { !$0.1.isEmpty }
                if tables.isEmpty {
                    Text(semantic.measureCount == 0 ? "Aucune mesure dans le modèle." : "Aucune mesure ne correspond.")
                        .foregroundStyle(.secondary)
                }
                ForEach(tables, id: \.0.name) { table, measures in
                    SectionHeader(table.name, count: measures.count)
                    MeasureFolderView(folder: MeasureFolder.tree(measures), table: table)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .environment(\.expansionCommand, command)
    }
}

struct MeasureFolderView: View {
    @EnvironmentObject var model: AppModel
    let folder: MeasureFolder
    let table: PBIPKit.Table

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(folder.folders, id: \.path) { sub in
                FolderDisclosure(folder: sub, table: table)
            }
            ForEach(folder.measures, id: \.self) { name in
                if let measure = table.measure(named: name) {
                    MeasureCard(table: table.name, measure: measure,
                                entry: model.entry(table: table.name, name: name), expanded: false, showsFolder: false)
                }
            }
        }
    }
}

struct FolderDisclosure: View {
    let folder: MeasureFolder
    let table: PBIPKit.Table
    @Environment(\.expansionCommand) private var command
    @State private var expanded = true

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            // AnyView : la vue est récursive (dossiers dans des dossiers).
            AnyView(MeasureFolderView(folder: folder, table: table))
                .padding(.leading, 12)
                .padding(.top, 6)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "folder").foregroundStyle(.secondary)
                Text(folder.name).bold()
                Text("\(folder.measureCount)").foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
            .onTapGesture { withAnimation { expanded.toggle() } }
        }
        .onAppear { if let command { expanded = command.expanded } }
        .onChange(of: command) { if let c = $0 { withAnimation { expanded = c.expanded } } }
    }
}

// MARK: - Pages et visuels

struct PagesOverviewView: View {
    @EnvironmentObject var model: AppModel
    let report: Report

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Pages et visuels").font(.title).bold()
                    Text("\(report.pages.count) pages · \(report.visualCount) visuels").foregroundStyle(.secondary)
                }
                ForEach(report.pages, id: \.id) { page in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(page.displayName).font(.title3).bold()
                            Text("\(page.visuals.count) visuels").foregroundStyle(.secondary)
                            Spacer()
                            Button("Ouvrir la page") { model.selection = .page(page.id) }
                        }
                        if !page.filters.isEmpty {
                            Text("Filtres de page : " + page.filters.map(\.displayName).joined(separator: ", "))
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                        HStack(alignment: .top, spacing: 16) {
                            PageCanvas(page: page, selection: .constant(nil))
                                .frame(width: 220)
                                .onTapGesture { model.selection = .page(page.id) }
                            VisualsGrid(page: page)
                        }
                    }
                    Divider()
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct VisualsGrid: View {
    @EnvironmentObject var model: AppModel
    let page: Page

    var body: some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 14, verticalSpacing: 6) {
            GridRow {
                Text("Type"); Text("Titre"); Text("Champs")
            }
            .font(.caption.bold())
            .foregroundStyle(.secondary)
            Divider()
            ForEach(page.visuals.sorted { ($0.position.y, $0.position.x) < ($1.position.y, $1.position.x) }, id: \.id) { visual in
                GridRow {
                    Text(visual.type).foregroundStyle(VisualBox.color(for: visual.type))
                    Text(visual.title ?? "(sans titre)").foregroundStyle(visual.title == nil ? .secondary : .primary)
                    Text(fields(visual))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    func fields(_ visual: Visual) -> String {
        let resolved = model.visualEntry(pageId: page.id, visualId: visual.id)?.fields.map(\.field.displayName)
            ?? visual.fields.map(\.displayName)
        return resolved.isEmpty ? "—" : resolved.joined(separator: ", ")
    }
}
