import PBIPKit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        NavigationSplitView {
            Sidebar()
                .navigationSplitViewColumnWidth(min: 200, ideal: 240)
        } detail: {
            Group {
                if model.project == nil {
                    EmptyState()
                } else {
                    Detail(item: model.selection)
                }
            }
        }
        .navigationTitle(model.project.map { $0.reportDisplayName ?? $0.name } ?? "PBIP Reader")
        .navigationSubtitle(subtitle)
        .toolbar {
            ToolbarItemGroup {
                Button { model.showOpenPanel() } label: { Label("Ouvrir", systemImage: "folder") }
                Button { model.reload() } label: { Label("Relire", systemImage: "arrow.clockwise") }
                    .disabled(model.url == nil)
            }
        }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url { Task { @MainActor in model.open(url) } }
            }
            return true
        }
        .alert("Impossible d'ouvrir le projet", isPresented: Binding(
            get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK") { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    var subtitle: String {
        guard let p = model.project else { return "" }
        var parts: [String] = []
        if let r = p.report { parts.append(r.format == .pbir ? "PBIR" : "PBIR-Legacy") }
        if let m = p.semanticModel { parts.append(m.format == .tmdl ? "TMDL" : "model.bim") }
        if p.datasetReference?.kind == .byConnection { parts.append("modèle publié") }
        return parts.joined(separator: " · ")
    }
}

struct EmptyState: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("Aucun projet ouvert").font(.title2)
            Text("Ouvrez un fichier .pbip ou un dossier .Report / .SemanticModel,\nou déposez-le dans cette fenêtre.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button("Ouvrir…") { model.showOpenPanel() }
                .keyboardShortcut("o")
                .controlSize(.large)
            Text("Lecture seule : aucun fichier n'est modifié.")
                .font(.footnote)
                .foregroundStyle(.tertiary)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Barre latérale

struct Sidebar: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        List(selection: $model.selection) {
            if model.visibleModel != nil || model.project?.report != nil {
                Section("Vue d'ensemble") {
                    if let semantic = model.visibleModel {
                        Label("Modèle", systemImage: "point.3.connected.trianglepath.dotted")
                            .tag(SidebarItem.diagram)
                        Label("Mesures", systemImage: "sum")
                            .badge(semantic.measureCount)
                            .tag(SidebarItem.measures)
                        if !semantic.functions.isEmpty {
                            Label("Fonctions", systemImage: "function")
                                .badge(semantic.functions.count)
                                .tag(SidebarItem.functions)
                        }
                        Label("Relations", systemImage: "arrow.triangle.branch")
                            .badge(semantic.relationships.count)
                            .tag(SidebarItem.relationships)
                    }
                    if let report = model.project?.report {
                        Label("Pages et visuels", systemImage: "rectangle.stack")
                            .badge(report.visualCount)
                            .tag(SidebarItem.pagesOverview)
                    }
                }
            }
            if let semantic = model.visibleModel {
                Section("Tables") {
                    ForEach(semantic.tables, id: \.name) { table in
                        Label(table.name, systemImage: table.calculationItems.isEmpty ? "tablecells" : "function")
                            .foregroundStyle(table.isHidden ? .secondary : .primary)
                            .badge(table.measures.count)
                            .tag(SidebarItem.table(table.name))
                    }
                    if !semantic.expressions.isEmpty {
                        Label("Requêtes M", systemImage: "curlybraces")
                            .badge(semantic.expressions.count)
                            .tag(SidebarItem.expressions)
                    }
                }
            } else if let ref = model.project?.datasetReference, ref.kind == .byConnection {
                Section("Modèle") {
                    Label(ref.modelName ?? "Modèle publié", systemImage: "icloud")
                        .foregroundStyle(.secondary)
                }
            }
            if let report = model.project?.report {
                Section("Rapport") {
                    ForEach(report.pages, id: \.id) { page in
                        Label(page.displayName, systemImage: "rectangle.on.rectangle")
                            .badge(page.visuals.count)
                            .tag(SidebarItem.page(page.id))
                    }
                }
            }
            if model.project != nil {
                Section("Diagnostics") {
                    Label("Diagnostics", systemImage: diagnosticIcon)
                        .badge(model.diagnostics.count)
                        .tag(SidebarItem.diagnostics)
                }
            }
        }
        .listStyle(.sidebar)
    }

    var diagnosticIcon: String {
        if model.diagnostics.hasErrors { return "xmark.octagon" }
        if model.diagnostics.contains(where: { $0.severity == .warning }) { return "exclamationmark.triangle" }
        return "checkmark.seal"
    }
}

// MARK: - Détail

struct Detail: View {
    @EnvironmentObject var model: AppModel
    let item: SidebarItem?

    var body: some View {
        switch item {
        case .diagram?:
            if let semantic = model.visibleModel {
                ModelDiagramView(semantic: semantic)
            }
        case .measures?:
            if let semantic = model.visibleModel {
                AllMeasuresView(semantic: semantic)
            }
        case .functions?:
            if let semantic = model.visibleModel {
                FunctionsView(semantic: semantic)
            }
        case .pagesOverview?:
            if let report = model.project?.report {
                PagesOverviewView(report: report)
            }
        case .table(let name)?:
            if let table = model.visibleModel?.table(named: name) {
                TableDetailView(table: table)
            }
        case .relationships?:
            RelationshipsView(relationships: model.visibleModel?.relationships ?? [])
        case .expressions?:
            ExpressionsView(expressions: model.project?.semanticModel?.expressions ?? [])
        case .page(let id)?:
            if let page = model.project?.report?.pages.first(where: { $0.id == id }) {
                PageDetailView(page: page)
            }
        case .diagnostics?:
            DiagnosticsView(diagnostics: model.diagnostics)
        case nil:
            Text("Sélectionnez un élément dans la barre latérale.")
                .foregroundStyle(.secondary)
        }
    }
}
