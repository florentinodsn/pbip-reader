import PBIPKit
import SwiftUI

/// Aperçu schématique d'une page, à partir des positions des visuels, et détail du visuel choisi.
struct PageDetailView: View {
    @EnvironmentObject var model: AppModel
    let page: Page
    @State private var selectedVisual: String?

    var body: some View {
        // HStack plutôt que HSplitView : imbriqué dans le détail d'un NavigationSplitView, HSplitView
        // débordait de la fenêtre et repoussait la barre latérale.
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text(page.displayName).font(.title).bold()
                    Text("\(Int(page.width))×\(Int(page.height)) · \(page.visuals.count) visuels")
                        .foregroundStyle(.secondary)
                }
                if !page.filters.isEmpty {
                    Text("Filtres de page : " + page.filters.map(\.displayName).joined(separator: ", "))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                PageCanvas(page: page, selection: $selectedVisual)
            }
            .padding(20)
            .frame(minWidth: 320, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            Divider()

            VisualInspector(page: page, visual: page.visuals.first { $0.id == selectedVisual })
                .frame(width: 280)
                .frame(maxHeight: .infinity)
        }
        .onChange(of: page.id) { _ in selectedVisual = nil }
    }
}

struct PageCanvas: View {
    let page: Page
    @Binding var selection: String?

    var body: some View {
        GeometryReader { geo in
            let width = max(page.width, 1)
            let height = max(page.height, 1)
            let scale = min(geo.size.width / width, geo.size.height / height)
            ZStack(alignment: .topLeading) {
                Rectangle()
                    .fill(Color(nsColor: .textBackgroundColor))
                    .overlay(Rectangle().stroke(Color(nsColor: .separatorColor)))
                    .frame(width: width * scale, height: height * scale)
                ForEach(page.visuals.sorted { $0.position.z < $1.position.z }, id: \.id) { visual in
                    VisualBox(visual: visual, selected: visual.id == selection)
                        .frame(width: max(visual.position.width * scale, 4), height: max(visual.position.height * scale, 4))
                        .offset(x: visual.position.x * scale, y: visual.position.y * scale)
                        .onTapGesture { selection = visual.id }
                }
            }
            .frame(width: width * scale, height: height * scale, alignment: .topLeading)
        }
        .aspectRatio(max(page.width, 1) / max(page.height, 1), contentMode: .fit)
    }
}

struct VisualBox: View {
    let visual: Visual
    let selected: Bool

    var body: some View {
        let color = Self.color(for: visual.type)
        RoundedRectangle(cornerRadius: 3)
            .fill(color.opacity(selected ? 0.35 : 0.15))
            .overlay(
                RoundedRectangle(cornerRadius: 3)
                    .strokeBorder(selected ? Color.accentColor : color.opacity(0.7),
                                  style: StrokeStyle(lineWidth: selected ? 2 : 1, dash: visual.type == "group" ? [4, 3] : []))
            )
            .overlay(alignment: .topLeading) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(visual.type).font(.caption2.bold())
                    if let t = visual.title { Text(t).font(.caption2).lineLimit(2) }
                }
                .padding(3)
                .foregroundStyle(.primary)
            }
            .clipped()
            .contentShape(Rectangle())
            .help(visual.title ?? visual.type)
    }

    /// Couleur stable par type de visuel.
    static func color(for type: String) -> Color {
        let palette: [Color] = [.blue, .green, .orange, .purple, .pink, .teal, .indigo, .brown, .mint, .cyan]
        let hash = type.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0x7fffffff }
        return type == "group" ? .gray : palette[hash % palette.count]
    }
}

struct VisualInspector: View {
    @EnvironmentObject var model: AppModel
    let page: Page
    let visual: Visual?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if let visual {
                    Text(visual.title ?? visual.type).font(.title3).bold()
                    Text("\(visual.type) · \(visual.id)").font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                    let p = visual.position
                    Text("x \(Int(p.x)), y \(Int(p.y)), z \(Int(p.z)) · \(Int(p.width))×\(Int(p.height))")
                        .font(.caption).foregroundStyle(.secondary)
                    Divider()
                    let resolved = model.visualEntry(pageId: page.id, visualId: visual.id)?.fields ?? []
                    if resolved.isEmpty {
                        Text("Aucun champ du modèle.").foregroundStyle(.secondary)
                    }
                    ForEach(Array(resolved.enumerated()), id: \.offset) { _, f in
                        FieldRow(field: f)
                    }
                } else {
                    Text("Cliquez sur un visuel de l'aperçu pour voir ses champs.")
                        .foregroundStyle(.secondary)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct FieldRow: View {
    let field: Lineage.ResolvedField

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: icon).foregroundStyle(color)
            VStack(alignment: .leading, spacing: 1) {
                Text(field.field.displayName).textSelection(.enabled)
                Text("\(field.field.role) · \(kind)\(statusText)").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    var kind: String {
        switch field.field.kind {
        case .measure: return "mesure"
        case .column: return "colonne"
        case .hierarchyLevel: return "niveau"
        }
    }

    var statusText: String {
        switch field.status {
        case .ok, .notChecked: return field.status == .notChecked ? " · non vérifié (modèle publié)" : ""
        case .unknownTable: return " · table inconnue"
        case .unknownField: return " · champ inconnu"
        case .kindMismatch: return " · type inversé"
        }
    }

    var icon: String {
        switch field.status {
        case .ok: return "checkmark.circle.fill"
        case .notChecked: return "circle.dotted"
        case .kindMismatch: return "exclamationmark.triangle.fill"
        case .unknownTable, .unknownField: return "xmark.circle.fill"
        }
    }

    var color: Color {
        switch field.status {
        case .ok: return .green
        case .notChecked: return .secondary
        case .kindMismatch: return .orange
        case .unknownTable, .unknownField: return .red
        }
    }
}

struct DiagnosticsView: View {
    let diagnostics: [Diagnostic]
    @State private var severity: Diagnostic.Severity?

    var shown: [Diagnostic] {
        diagnostics.filter { severity == nil || $0.severity == severity }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Diagnostics").font(.title).bold()
                    Spacer()
                    Picker("Gravité", selection: $severity) {
                        Text("Tous (\(diagnostics.count))").tag(Diagnostic.Severity?.none)
                        ForEach(Diagnostic.Severity.allCases, id: \.self) { s in
                            Text("\(label(s)) (\(diagnostics.filter { $0.severity == s }.count))").tag(Diagnostic.Severity?.some(s))
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(maxWidth: 420)
                }
                if shown.isEmpty {
                    Label("Aucun diagnostic.", systemImage: "checkmark.seal").foregroundStyle(.secondary)
                }
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(shown.enumerated()), id: \.offset) { i, d in
                        if i > 0 { Divider() }
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Image(systemName: icon(d.severity)).foregroundStyle(color(d.severity))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(d.message).textSelection(.enabled)
                                Text([d.code, d.file.map { f in d.line.map { "\(f):\($0)" } ?? f }].compactMap { $0 }.joined(separator: " · "))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                            }
                        }
                        .padding(.vertical, 6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    func label(_ s: Diagnostic.Severity) -> String {
        switch s {
        case .error: return "Erreurs"
        case .warning: return "Avertissements"
        case .info: return "Infos"
        }
    }

    func icon(_ s: Diagnostic.Severity) -> String {
        switch s {
        case .error: return "xmark.octagon.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .info: return "info.circle.fill"
        }
    }

    func color(_ s: Diagnostic.Severity) -> Color {
        switch s {
        case .error: return .red
        case .warning: return .orange
        case .info: return .blue
        }
    }
}
