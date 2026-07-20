import SwiftUI
#if canImport(UIKit)
import UIKit
#endif
#if canImport(AppKit)
import AppKit
#endif
// GarageHUDKit sources are compiled directly into this target (see project.pbxproj
// synchronized group), so RootView is in-module — no import needed.

@main
struct GarageHUDApp: App {
    #if canImport(UIKit)
    @UIApplicationDelegateAdaptor(PushDelegate.self) private var pushDelegate
    #elseif canImport(AppKit)
    @NSApplicationDelegateAdaptor(PushDelegate.self) private var pushDelegate
    #endif

    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}

/// Receives iCloud's silent "the garage changed elsewhere" nudge (W-068).
///
/// GarageHUD used to fetch only at launch and on becoming active, so an app left open — a Mac
/// sitting frontmost in the garage — never learned the phone had written anything, and a correct
/// sync looked like data loss. This delegate exists solely to turn that nudge into a fetch.
///
/// It is silent by construction: the subscription sets `shouldSendContentAvailable`, which wakes the
/// app without an alert, badge, sound, or permission prompt. Notably it does **not** ask for
/// notification authorization — this is plumbing, not a notifications feature, and asking would put
/// a dialog in front of the owner for something they should never see.
///
/// The push carries no garage data and is never trusted with any: it only says "look again". What to
/// believe is decided entirely by the existing guarded pull and the stamped merge.
final class PushDelegate: NSObject {
    /// Posted on the main queue when iCloud reports a remote change.
    static let remoteChange = Notification.Name("GarageHUD.remoteChangeNoticed")

    private func handleRemoteNotification() {
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: Self.remoteChange, object: nil)
        }
    }
}

#if canImport(UIKit)
extension PushDelegate: UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        application.registerForRemoteNotifications()
        return true
    }

    func application(_ application: UIApplication,
                     didReceiveRemoteNotification userInfo: [AnyHashable: Any],
                     fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        handleRemoteNotification()
        // .newData rather than .noData: the fetch this triggers is asynchronous, and reporting
        // no-data would teach iOS to deliver these less often — quietly reintroducing the staleness
        // this exists to fix.
        completionHandler(.newData)
    }

    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        // Simulator, no network, or no push entitlement. Launch/foreground fetching still works, so
        // the app stays correct — just not as fresh.
    }
}
#elseif canImport(AppKit)
extension PushDelegate: NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.registerForRemoteNotifications()
    }

    func application(_ application: NSApplication, didReceiveRemoteNotification userInfo: [String: Any]) {
        handleRemoteNotification()
    }

    func application(_ application: NSApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        // Unsigned or unentitled desktop build — degrade to launch/foreground fetching.
    }
}
#endif
