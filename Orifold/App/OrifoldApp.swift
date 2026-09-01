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
        .defaultSize(
            width: PrimaryWindowSizing.defaultContentSize.width,
            height: PrimaryWindowSizing.defaultContentSize.height
        )
        .windowResizability(.contentMinSize)
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
        // verbatim `StringProtocol` overload) via `L10n.string` instead. The scene-title
        // argument is only read when the scene is first built, so `.navigationTitle` on
        // the content re-titles the live window when the language changes.
        Window(L10n.string("window.about.title"), id: "about-orifold") {
            AppAboutPopover()
                .environmentObject(languageManager)
                .environment(\.locale, languageManager.effectiveLocale)
                .navigationTitle(L10n.string("window.about.title", locale: languageManager.effectiveLocale))
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)

        Window(L10n.string("window.softwareUpdate.title"), id: SoftwareUpdateWindow.id) {
            SoftwareUpdateView()
                .environmentObject(languageManager)
                .environment(\.locale, languageManager.effectiveLocale)
                .navigationTitle(L10n.string("window.softwareUpdate.title", locale: languageManager.effectiveLocale))
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
#if DEBUG
    private var cleanupAccessibilityAcceptanceWindow: NSWindow?
#endif

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Register the bundled substitution fonts before the first editor render, so
        // unembedded Arial/Times/Calibri/… resolve to their metric-compatible faces.
        FontRegistrar.registerBundledFonts()

#if DEBUG
        // A temporary debug bundle can opt into the real cleanup-row accessibility surface
        // by setting this private Info.plist key. Release builds contain neither this branch
        // nor the harness view, and ordinary debug launches remain unchanged.
        if Bundle.main.object(forInfoDictionaryKey: "OrifoldCleanupAccessibilityAcceptance") as? Bool == true {
            let hostingView = NSHostingView(rootView: ScanCleanupAccessibilityAcceptanceView())
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 430, height: 260),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.title = "Orifold Cleanup Accessibility Acceptance"
            window.contentView = hostingView
            window.center()
            window.makeKeyAndOrderFront(nil)
            cleanupAccessibilityAcceptanceWindow = window
            NSApp.activate(ignoringOtherApps: true)
            return
        }
#endif

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
