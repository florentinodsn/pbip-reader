import PBIPKit
import SwiftUI

/// Détail d'une table : colonnes, mesures (avec DAX et usages), hiérarchies, partitions.
struct TableDetailView: View {
    @EnvironmentObject var model: AppModel
    let table: PBIPKit.Table

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(table.name).font(.title).bold()
                        if table.isHidden { Tag("masquée") }
                    }
                    if let d = table.description { Text(d).foregroundStyle(.secondary) }
                }

                if !table.measures.isEmpty {
                    SectionHeader("Mesures", count: table.measures.count)
                    ForEach(table.measures, id: \.name) { measure in
                        MeasureCard(table: table.name, measure: measure, entry: model.entry(table: table.name, name: measure.name))
                    }
                }

                if !table.columns.isEmpty {
                    SectionHeader("Colonnes", count: table.columns.count)
                    ColumnsGrid(table: table)
                }

                if !table.hierarchies.isEmpty {
                    SectionHeader("Hiérarchies", count: table.hierarchies.count)
                    ForEach(table.hierarchies, id: \.name) { h in
                        HStack {
                            Text(h.name).bold()
                            Text(h.levels.map(\.name).joined(separator: " › ")).foregroundStyle(.secondary)
                        }
                    }
                }

                if !table.calculationItems.isEmpty {
                    SectionHeader("Éléments de calcul", count: table.calculationItems.count)
                    ForEach(table.calculationItems, id: \.name) { item in
                        Text(item.name).bold()
                        CodeView(code: item.expression, language: .dax)
                    }
                }

                if !table.partitions.isEmpty {
                    SectionHeader("Partitions", count: table.partitions.count)
                    ForEach(table.partitions, id: \.name) { p in
                        HStack {
                            Text(p.name).bold()
                            Tag(p.sourceKind)
                            if let mode = p.mode { Tag(mode) }
                        }
                        if let e = p.expression {
                            CodeView(code: e, language: p.sourceKind == "m" ? .m : .dax)
                        }
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct MeasureCard: View {
    let table: String
    let measure: Measure
    let entry: Lineage.Entry?
    /// Faux quand la mesure est déjà affichée dans son dossier.
    var showsFolder = true
    @Environment(\.expansionCommand) private var command
    @State private var expanded: Bool

    init(table: String, measure: Measure, entry: Lineage.Entry?, expanded: Bool = true, showsFolder: Bool = true) {
        self.table = table
        self.measure = measure
        self.entry = entry
        self.showsFolder = showsFolder
        _expanded = State(initialValue: expanded)
    }

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: 8) {
                if let d = measure.description {
                    Text(d).foregroundStyle(.secondary)
                }
                CodeView(code: measure.expression, language: .dax)
                if let entry {
                    UsageList(entry: entry)
                }
            }
            .padding(.top, 6)
        } label: {
            HStack(spacing: 8) {
                Text(measure.name).bold()
                if let f = measure.formatString { Tag(f) }
                if showsFolder, let folder = measure.displayFolder { Tag("📁 \(folder)") }
                if measure.isHidden { Tag("masquée") }
                if let entry, entry.usedBy.isEmpty, entry.referencedBy.isEmpty {
                    Tag("inutilisée", color: .orange)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { withAnimation { expanded.toggle() } }
        }
        .onAppear { if let command { expanded = command.expanded } }
        .onChange(of: command) { if let c = $0 { withAnimation { expanded = c.expanded } } }
    }
}

/// Visuels et mesures qui utilisent un objet ; objets qu'il référence.
struct UsageList: View {
    let entry: Lineage.Entry

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(entry.usedBy, id: \.self) { usage in
                Label(usage.label, systemImage: "rectangle.on.rectangle").font(.callout)
            }
            ForEach(entry.referencedBy, id: \.self) { name in
                Label("utilisée par \(name)", systemImage: "arrow.turn.up.left").font(.callout)
            }
            ForEach(entry.references, id: \.self) { name in
                Label("référence \(name)", systemImage: "arrow.turn.down.right").font(.callout).foregroundStyle(.secondary)
            }
        }
    }
}

struct ColumnsGrid: View {
    @EnvironmentObject var model: AppModel
    let table: PBIPKit.Table

    var body: some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 16, verticalSpacing: 6) {
            GridRow {
                Text("Nom"); Text("Type"); Text("Source"); Text("Format"); Text("Utilisée")
            }
            .font(.caption.bold())
            .foregroundStyle(.secondary)
            Divider()
            ForEach(table.columns, id: \.name) { c in
                GridRow {
                    Text(c.name).foregroundStyle(c.isHidden ? .secondary : .primary)
                    Text(c.dataType ?? "").foregroundStyle(.secondary)
                    if let e = c.expression {
                        Text(e).font(.system(.callout, design: .monospaced)).lineLimit(2)
                    } else {
                        Text(c.sourceColumn ?? "").foregroundStyle(.secondary)
                    }
                    Text(c.formatString ?? "").foregroundStyle(.secondary)
                    Text(usage(c))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    func usage(_ c: Column) -> String {
        guard let entry = model.entry(table: table.name, name: c.name) else { return "" }
        let count = entry.usedBy.count + entry.referencedBy.count
        return count == 0 ? "" : "\(count)×"
    }
}

struct RelationshipsView: View {
    let relationships: [Relationship]

    enum Filter: Hashable {
        case all, table, column
    }

    @State private var filter = Filter.all
    @State private var table = ""
    @State private var column = ""

    /// Noms sans doublon de casse (les références sont insensibles à la casse), triés.
    static func distinct(_ names: [String]) -> [String] {
        var seen = Set<String>()
        return names.filter { seen.insert($0.lowercased()).inserted }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    var tables: [String] { Self.distinct(relationships.flatMap { [$0.from.table, $0.to.table] }) }
    var columns: [String] { Self.distinct(relationships.flatMap { [$0.from.displayName, $0.to.displayName] }) }

    var shown: [Relationship] {
        func same(_ a: String, _ b: String) -> Bool { a.caseInsensitiveCompare(b) == .orderedSame }
        switch filter {
        case .all: return relationships
        case .table: return relationships.filter { same($0.from.table, table) || same($0.to.table, table) }
        case .column: return relationships.filter { same($0.from.displayName, column) || same($0.to.displayName, column) }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Relations").font(.title).bold()
                    Text(filter == .all ? "\(relationships.count)" : "\(shown.count) / \(relationships.count)")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Picker("Filtrer", selection: $filter) {
                        Text("Toutes").tag(Filter.all)
                        Text("Par table").tag(Filter.table)
                        Text("Par colonne").tag(Filter.column)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                    if filter == .table {
                        Picker("Table", selection: $table) {
                            ForEach(tables, id: \.self) { Text($0).tag($0) }
                        }
                        .labelsHidden()
                        .frame(maxWidth: 220)
                    } else if filter == .column {
                        Picker("Colonne", selection: $column) {
                            ForEach(columns, id: \.self) { Text($0).tag($0) }
                        }
                        .labelsHidden()
                        .frame(maxWidth: 260)
                    }
                }
                Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 16, verticalSpacing: 8) {
                    GridRow {
                        Text("De"); Text(""); Text("Vers"); Text("Cardinalité"); Text("Filtrage"); Text("Active")
                    }
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                    Divider()
                    ForEach(shown, id: \.id) { r in
                        GridRow {
                            Text(r.from.displayName)
                            Image(systemName: r.crossFilteringBehavior == "bothDirections" ? "arrow.left.and.right" : "arrow.left")
                                .foregroundStyle(.secondary)
                            Text(r.to.displayName)
                            Text(r.cardinality)
                            Text(r.crossFilteringBehavior).foregroundStyle(.secondary)
                            Image(systemName: r.isActive ? "checkmark" : "minus")
                                .foregroundStyle(r.isActive ? Color.green : Color.secondary)
                        }
                    }
                }
                if shown.isEmpty {
                    Text("Aucune relation.").foregroundStyle(.secondary)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onChange(of: filter) { _ in
            if !tables.contains(table) { table = tables.first ?? "" }
            if !columns.contains(column) { column = columns.first ?? "" }
        }
    }
}

struct ExpressionsView: View {
    let expressions: [NamedExpression]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Requêtes M et paramètres").font(.title).bold()
                ForEach(expressions, id: \.name) { e in
                    HStack {
                        Text(e.name).bold()
                        if e.isParameter { Tag("paramètre") }
                    }
                    if let d = e.description { Text(d).foregroundStyle(.secondary) }
                    CodeView(code: e.expression, language: .m)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Petits composants

struct SectionHeader: View {
    let title: String
    let count: Int

    init(_ title: String, count: Int) {
        self.title = title
        self.count = count
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.title3).bold()
            Text("\(count)").foregroundStyle(.secondary)
        }
        .padding(.top, 4)
    }
}

struct Tag: View {
    let text: String
    var color: Color = .secondary

    init(_ text: String, color: Color = .secondary) {
        self.text = text
        self.color = color
    }

    var body: some View {
        Text(text)
            .font(.caption)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .foregroundStyle(color)
            .background(color.opacity(0.12), in: Capsule())
    }
}
