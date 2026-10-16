import AppIntents
import MarskalKit

struct AppIntents: AppIntentsPackage {
    static var includedPackages: [any AppIntentsPackage.Type] { [MarskalKitIntents.self] }
}

/// The actions Siri and Spotlight offer without setup (ADR 0029). A phrase
/// cannot hold a free-text title, so Siri asks for it.
struct MarskalShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AddToInboxIntent(),
            phrases: [
                "Add to \(.applicationName) Inbox",
                "Add to my \(.applicationName) Inbox",
                "Add a task to \(.applicationName)",
                "Capture in \(.applicationName)",
            ],
            shortTitle: "Add to Inbox",
            systemImageName: "tray.and.arrow.down"
        )
    }
}
