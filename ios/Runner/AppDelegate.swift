import UIKit
import Flutter
import Firebase
import FirebaseCore
import FirebaseMessaging

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Configure Firebase
    FirebaseApp.configure()
    
    GeneratedPluginRegistrant.register(with: self)

    // 👇 Background task channel for video uploads
    let controller = window?.rootViewController as! FlutterViewController
    let channel = FlutterMethodChannel(name: "com.drivelife/background_task",
                                       binaryMessenger: controller.binaryMessenger)
    var bgTaskId: UIBackgroundTaskIdentifier = .invalid

    channel.setMethodCallHandler { call, result in
      if call.method == "beginBackgroundTask" {
        bgTaskId = application.beginBackgroundTask {
          application.endBackgroundTask(bgTaskId)
          bgTaskId = .invalid
        }
        result(String(bgTaskId.rawValue))
      } else if call.method == "endBackgroundTask" {
        if bgTaskId != .invalid {
          application.endBackgroundTask(bgTaskId)
          bgTaskId = .invalid
        }
        result(nil)
      }
    }
    // 👆 End background task channel

    // ── The number on the app icon ──────────────────────────────────
    //
    // iOS keeps no count of its own. The badge is whatever the last
    // push PUT there, and nothing takes it off when the person reads
    // their notifications inside the app -- so without this it sticks
    // at the last number a push carried until another push corrects
    // it. Android needs none of this: it counts the notifications it
    // is showing and clears them when they are opened.
    //
    // A channel rather than a package: this is the whole of what is
    // needed on one platform, and it is fewer lines than the podspec
    // of anything that would do it for us.
    let badgeChannel = FlutterMethodChannel(name: "drivelife/badge",
                                            binaryMessenger: controller.binaryMessenger)

    badgeChannel.setMethodCallHandler { call, result in
      guard call.method == "setBadge" else {
        result(FlutterMethodNotImplemented)
        return
      }

      let args = call.arguments as? [String: Any]
      let count = max(0, (args?["count"] as? Int) ?? 0)

      // setBadgeCount is the iOS 16+ API and the only one that is not
      // deprecated. applicationIconBadgeNumber still works below it
      // and must be touched on the main thread.
      if #available(iOS 16.0, *) {
        UNUserNotificationCenter.current().setBadgeCount(count) { error in
          if let error = error {
            print("⚠️ Could not set the badge: \(error)")
          }
        }
      } else {
        DispatchQueue.main.async {
          application.applicationIconBadgeNumber = count
        }
      }

      result(nil)
    }
    // 👆 End badge channel
    
    // Setup notifications
    if #available(iOS 10.0, *) {
      UNUserNotificationCenter.current().delegate = self
      
      let authOptions: UNAuthorizationOptions = [.alert, .badge, .sound]
      UNUserNotificationCenter.current().requestAuthorization(
        options: authOptions,
        completionHandler: { granted, error in
          if granted {
            print("✅ Notification permission granted")
          } else {
            print("❌ Notification permission denied")
          }
        }
      )
    } else {
      let settings: UIUserNotificationSettings =
        UIUserNotificationSettings(types: [.alert, .badge, .sound], categories: nil)
      application.registerUserNotificationSettings(settings)
    }
    
    application.registerForRemoteNotifications()
    
    // Set messaging delegate
    Messaging.messaging().delegate = self
    
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
  
  override func application(_ application: UIApplication,
                            didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
    print("✅ APNs token received")
    Messaging.messaging().apnsToken = deviceToken
  }
  
  override func application(_ application: UIApplication,
                            didFailToRegisterForRemoteNotificationsWithError error: Error) {
    print("❌ Failed to register for remote notifications: \(error)")
  }
}

// MARK: - MessagingDelegate
extension AppDelegate: MessagingDelegate {
  func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
    print("✅ Firebase registration token: \(String(describing: fcmToken))")
    
    let dataDict: [String: String] = ["token": fcmToken ?? ""]
    NotificationCenter.default.post(
      name: Notification.Name("FCMToken"),
      object: nil,
      userInfo: dataDict
    )
  }
}