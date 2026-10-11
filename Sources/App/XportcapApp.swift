import SwiftUI
import AppKit

@main
struct XportcapApp: App {
    @State private var library = Library()
    @State private var exports = ExportQueue()
    @State private var splashDone = false  // once per launch, not per window

    init() {
        CLI.runIfRequested()  // exits when a command-line mode was requested
        NSApplication.shared.setActivationPolicy(.regular)
    }

    @AppStorage("appearance") private var appearance = "dark"

    var body: some Scene {
        // single window: reopening from the Dock reuses it instead of spawning a new one (and a new splash)
        Window("Xportcap", id: "main") {
            RootView(splashDone: $splashDone)
                .environment(library)
                .environment(exports)
                .frame(minWidth: 860, minHeight: 540)
                .preferredColorScheme(appearance == "light" ? .light : appearance == "dark" ? .dark : nil)
                .onAppear { NSApp.activate() }
        }
        .windowToolbarStyle(.unified)
    }
}
