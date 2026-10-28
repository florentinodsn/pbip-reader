import AppKit
import Foundation
import PBIPKit

/// Élément sélectionné dans la barre latérale.
enum SidebarItem: Hashable {
    case diagram
    case measures
    case functions
    case pagesOverview
    case table(String)
    case relationships
    case expressions
    case page(String)
    case diagnostics
}

/// État de l'application : un projet ouvert, en lecture seule.
@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var url: URL?
    @Published private(set) var project: Project?
    /// Modèle affiché : sans les tables de date automatiques, inutiles à la lecture.
    @Published private(set) var visibleModel: SemanticModel?
    @Published private(set) var lineage = Lineage()
    @Published private(set) var diagnostics: [Diagnostic] = []
    @Published var selection: SidebarItem?
    @Published var errorMessage: String?

    func open(_ url: URL) {
        do {
            let project = try ProjectLoader().load(url)
            let lineage = LineageBuilder.build(project)
            self.url = url
            self.project = project
            self.visibleModel = project.semanticModel?.withoutAutoDateTables
            self.lineage = lineage
            self.diagnostics = Validator.validate(project, lineage: lineage)
            self.errorMessage = nil
            if selection == nil || !isValid(selection!) {
                selection = project.semanticModel != nil ? .diagram
                    : project.report != nil ? .pagesOverview
                    : .diagnostics
            }
            NSDocumentController.shared.noteNewRecentDocumentURL(url)
        } catch {
            errorMessage = "\(error)"
        }
    }

    func reload() {
        if let url { open(url) }
    }

    func showOpenPanel() {
        let panel = NSOpenPanel()
        panel.title = "Ouvrir un projet PBIP"
        panel.message = "Choisissez un fichier .pbip, ou un dossier .Report / .SemanticModel."
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            open(url)
        }
    }

    private func isValid(_ item: SidebarItem) -> Bool {
        switch item {
        case .table(let name): return visibleModel?.table(named: name) != nil
        case .page(let id): return project?.report?.pages.contains { $0.id == id } == true
        case .diagram, .measures, .relationships, .expressions: return project?.semanticModel != nil
        case .functions: return visibleModel?.functions.isEmpty == false
        case .pagesOverview: return project?.report != nil
        case .diagnostics: return true
        }
    }

    /// Utilisations d'un objet du modèle dans le rapport.
    func entry(table: String, name: String) -> Lineage.Entry? {
        lineage.entries.first {
            $0.table.caseInsensitiveCompare(table) == .orderedSame && $0.name.caseInsensitiveCompare(name) == .orderedSame
        }
    }

    func visualEntry(pageId: String, visualId: String) -> Lineage.VisualEntry? {
        lineage.visuals.first { $0.pageId == pageId && $0.visualId == visualId }
    }
}
