// LibreScreen
// Copyright (c) 2026 Renato Asterio
// Licensed under the PolyForm Noncommercial License 1.0.0

import SwiftUI

@main
struct LibreScreenApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra(isInserted: menuBarInserted) {
            MenuBarMenuView()
                .environment(appDelegate.container)
        } label: {
            MenuBarLabel()
                .environment(appDelegate.container)
        }

        Settings {
            SettingsView()
                .environment(appDelegate.container)
        }
        .commands {
            AppCommands(container: appDelegate.container)
        }
    }

    /// SwiftUI calls this setter on every graph update; writing an unchanged value would invalidate the
    /// observed settings and re-trigger the update in a loop, so only real changes are stored.
    private var menuBarInserted: Binding<Bool> {
        Binding(
            get: { appDelegate.container.settings.settings.general.showsMenuBarExtra },
            set: { newValue in
                let store = appDelegate.container.settings
                if store.settings.general.showsMenuBarExtra != newValue {
                    store.settings.general.showsMenuBarExtra = newValue
                }
            }
        )
    }
}
