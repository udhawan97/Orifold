import SwiftUI
import AppKit

@main
struct OrifoldApp: App {
    @NSApplicationDelegateAdaptor(OrifoldAppDelegate.self) private var appDelegate

    var body: some Scene {
        DocumentGroup(newDocument: { WorkspaceDocument() }) { config in
            ContentView(document: config.document)
        }
        .commands {
            AppCommands()
        }
    }
}

final class OrifoldAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            guard NSDocumentController.shared.documents.isEmpty else { return }

            let visibleDocumentWindows = NSApp.windows.filter { window in
                window.isVisible && !window.isMiniaturized && window.contentViewController != nil
            }
            guard visibleDocumentWindows.isEmpty else { return }

            NSDocumentController.shared.newDocument(nil)
        }
    }
}
