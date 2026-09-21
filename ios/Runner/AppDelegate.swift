import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // ⚠️ This assignment must happen BEFORE plugin registration, and that is
    // the only reason this override exists.
    //
    // `FlutterAppDelegate` already conforms to UNUserNotificationCenterDelegate
    // and forwards the callbacks that flutter_local_notifications listens for.
    // But whoever is the delegate at the instant iOS delivers the notification
    // *response* is the only object that sees it, and for a cold start — the
    // user tapping a reminder on the lock screen — that instant is immediately
    // after launch.
    //
    // Register the plugins first and the delegate is installed one turn too
    // late: `consumeLaunchPayload()` returns nil, the router has no task id to
    // open, and the app lands on Home. The bug report reads "tapping a reminder
    // opens Home", which sends the next maintainer straight into go_router and
    // the notification payload encoding — neither of which is broken.
    //
    // `super.application(…)` is what brings up the implicit engine and thus
    // calls `didInitializeImplicitFlutterEngine` below, so setting the delegate
    // before that call is what guarantees the ordering regardless of when the
    // engine happens to be created.
    UNUserNotificationCenter.current().delegate = self

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}
