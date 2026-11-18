import SwiftUI
import UserNotifications

@main
struct StatuspageMenuBarApp: App {
    @StateObject private var model = StatusModel()

    init() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    var body: some Scene {
        MenuBarExtra {
            StatusMenuView(model: model)
        } label: {
            if model.indicator == "none" {
                Image(systemName: model.iconName)
            } else {
                Image(systemName: model.iconName)
                    .renderingMode(.original)
                    .foregroundStyle(model.iconColor)
                    .opacity(model.iconOpacity)
            }
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(model: model)
        }
    }
}
