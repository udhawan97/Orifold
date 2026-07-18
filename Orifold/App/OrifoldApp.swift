import SwiftUI
import AppKit

@main
struct OrifoldApp: App {
    @NSApplicationDelegateAdaptor(OrifoldAppDelegate.self) private var appDelegate
    @StateObject private var languageManager = LanguageManager()

    var body: some Scene {
        DocumentGroup(newDocument: { WorkspaceDocument() }) { config in
            ContentView(document: config.document, fileURL: config.fileURL)
                .environmentObject(languageManager)
                .environment(\.locale, languageManager.effectiveLocale)
        }
        .commands {
            // `.commands {}` is a separate branch of the scene graph from the
            // DocumentGroup's window content — it doesn't inherit the
            // `.environment(\.locale:)` override applied to `ContentView` above
            // (and `Commands`, unlike `View`, has no `.environmentObject`/
            // `.environment` modifier to reapply it), so the language manager is
            // passed down directly instead.
            AppCommands(languageManager: languageManager)
        }
        .environmentObject(languageManager)

        // `Window`'s title parameter is a `LocalizedStringKey`, which resolves against
        // `Bundle.main` — but the shipped app is built with pure SwiftPM, whose catalog
        // lives in a nested `Orifold_Orifold.bundle`, so a key literal here renders the
        // raw `window.*.title` on screen. Pass a pre-resolved `String` (selects the
        // verbatim `StringProtocol` overload) via `L10n.string` instead. Scene titles are
        // built once at launch, so this reflects the launch-time language.
        Window(L10n.string("window.about.title"), id: "about-orifold") {
            AppAboutPopover()
                .environmentObject(languageManager)
                .environment(\.locale, languageManager.effectiveLocale)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)

        Window(L10n.string("window.softwareUpdate.title"), id: SoftwareUpdateWindow.id) {
            SoftwareUpdateView()
                .environmentObject(languageManager)
                .environment(\.locale, languageManager.effectiveLocale)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)

        Settings {
            SettingsView()
                .environmentObject(languageManager)
                .environment(\.locale, languageManager.effectiveLocale)
        }
    }
}

final class OrifoldAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Register the bundled substitution fonts before the first editor render, so
        // unembedded Arial/Times/Calibri/… resolve to their metric-compatible faces.
        FontRegistrar.registerBundledFonts()

        UpdateLaunchCoordinator.shared.applicationDidFinishLaunching()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            guard NSDocumentController.shared.documents.isEmpty else { return }

            let visibleDocumentWindows = NSApp.windows.filter { window in
                window.isVisible && !window.isMiniaturized && window.contentViewController != nil
            }
            guard visibleDocumentWindows.isEmpty else { return }

            NSDocumentController.shared.newDocument(nil)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        UpdateLaunchCoordinator.shared.applicationWillTerminate()
    }
}
