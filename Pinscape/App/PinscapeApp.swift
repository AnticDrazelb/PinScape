import SwiftUI
import TipKit
import UIKit
import UserNotifications

@main
struct PinscapeApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(AppModel.shared)
                .environment(LocationEngine.shared)
                .environment(ProStore.shared)
                .modelContainer(PinStore.container)
                .tint(Theme.accent)
                .onOpenURL { AppModel.shared.open($0) }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            AppModel.shared.handlePendingRoute()
            AppModel.shared.refreshVisits()
            if AppGroup.defaults.bool(forKey: SharedKeys.needsReplan) {
                LocationEngine.shared.scheduleReplan()
            }
            Task {
                await LiveActivityController.resumeForCurrentVisits()
                await CalendarScout.shared.refresh()
            }
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        NotificationManager.registerCategories()
        PinscapeHooks.openRoute = { route in
            AppModel.shared.open(route: route)
        }
        if PinStore.isDemo {
            DemoContent.install()
        } else {
            try? Tips.configure([.displayFrequency(.daily)])
        }
        // Starts geofence monitoring. When iOS relaunches Pinscape in the background
        // because you arrived somewhere, this is what receives the event.
        LocationEngine.shared.start()
        ProStore.shared.start()
        return true
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let action = response.actionIdentifier
        let info = response.notification.request.content.userInfo
        let pinIDs = info["pinIDs"] as? [String] ?? []
        let regionID = info["regionID"] as? String
        let route = info["route"] as? String
        let place = info["place"] as? String
        await MainActor.run {
            if route == "capture" {
                AppModel.shared.startCapture(text: place.map { "\($0), " } ?? "", listen: true)
            } else {
                NotificationManager.handle(action: action, pinIDs: pinIDs, regionID: regionID)
            }
        }
    }
}

/// Lets a shake anywhere in the app undo the last capture.
extension UIWindow {
    open override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        if motion == .motionShake {
            NotificationCenter.default.post(name: .pinscapeShake, object: nil)
        }
        super.motionEnded(motion, with: event)
    }
}

extension Notification.Name {
    static let pinscapeShake = Notification.Name("PinscapeShake")
}
