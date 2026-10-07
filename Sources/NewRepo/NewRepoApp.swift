import SwiftUI

@main
struct NewRepoApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // Everything lives in the menu bar popover managed by AppDelegate.
        Settings { EmptyView() }
    }
}
