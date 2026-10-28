import AppKit
import SwiftUI

/// Exécutable SwiftPM sans bundle : il faut déclarer l'application comme « normale »
/// pour qu'elle ait une fenêtre au premier plan et une entrée dans le Dock.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.regular)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@main
struct PBIPReaderApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup("PBIP Reader") {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 900, minHeight: 560)
                .onAppear {
                    // `pbip-reader-app -project <chemin>` ouvre directement le projet. Un chemin passé
                    // seul serait pris par AppKit pour un document à ouvrir, et SwiftUI ne créerait
                    // alors pas la fenêtre initiale : on le lit donc comme une option.
                    if model.project == nil, let path = UserDefaults.standard.string(forKey: "project") {
                        model.open(URL(fileURLWithPath: path))
                    }
                }
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Ouvrir…") { model.showOpenPanel() }
                    .keyboardShortcut("o")
                Button("Relire le projet") { model.reload() }
                    .keyboardShortcut("r")
                    .disabled(model.url == nil)
            }
        }
    }
}
