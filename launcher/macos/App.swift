import SwiftUI

@main
struct GoW2RecompApp: App {
    @StateObject private var backend = Backend()
    @StateObject private var settings = GameSettings()
    @StateObject private var patches = PatchStore()

    var body: some Scene {
        WindowGroup("GoW2 Recomp") {
            ContentView()
                .environmentObject(backend)
                .environmentObject(settings)
                .environmentObject(patches)
                .frame(minWidth: 860, minHeight: 560)
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Jogar") { backend.play(resume: false, settings: settings, patchFile: patches.writePatchFile()) }
                    .keyboardShortcut("r")
                    .disabled(backend.running || !(backend.status?.setup_ok ?? false))
            }
        }
    }
}
