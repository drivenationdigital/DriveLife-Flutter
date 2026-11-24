import UIKit
import Flutter
import Firebase
import FirebaseCore
import FirebaseMessaging
import StoreKit

@main
@objc class AppDelegate: FlutterAppDelegate {

  /// StoreKit's subscription state as a word the app can read.
  ///
  /// Deliberately NOT used to decide entitlement -- that stays with
  /// the expiry date and, once it exists, the server. This is for
  /// wording only: what to tell somebody about where they stand.
  @available(iOS 15.0, *)
  static func stateName(_ state: Product.SubscriptionInfo.RenewalState) -> String {
    switch state {
    case .subscribed:           return "subscribed"
    case .expired:              return "expired"
    case .inBillingRetryPeriod: return "billingRetry"
    case .inGracePeriod:        return "grace"
    case .revoked:              return "revoked"
    default:                    return "unknown"
    }
  }

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
    
    // ── WILL IT RENEW? ──────────────────────────────────────────────
    //
    // in_app_purchase does not say. It reports WHAT is owned and when
    // it expires, and nothing at all about whether it is set to renew
    // -- because that lives on RenewalInfo, which the plugin has no
    // wrapper for on either platform's Dart side.
    //
    // Without it the paywall cannot tell a member who is happily
    // subscribed from one who cancelled an hour ago, and it offers
    // both of them "Manage or cancel". The second person has already
    // cancelled. The screen is lying to them, and the thing they
    // actually want -- to come back -- is not on it.
    //
    // Android gets this free: isAutoRenewing is on the Play purchase
    // and readable in Dart. iOS needs these thirty lines.
    //
    // Works against a local .storekit configuration exactly as it does
    // against the App Store, because it is the real StoreKit 2 API
    // either way -- so cancelling in Xcode's Transaction Manager shows
    // up here immediately.
    let subscriptionChannel = FlutterMethodChannel(
      name: "drivelife/subscription",
      binaryMessenger: controller.binaryMessenger)

    subscriptionChannel.setMethodCallHandler { call, result in
      guard call.method == "renewalStatus" else {
        result(FlutterMethodNotImplemented)
        return
      }

      guard #available(iOS 15.0, *) else {
        // StoreKit 2 starts at iOS 15. Below it the app falls back to
        // "unknown", which draws the cautious wording rather than
        // claiming a renewal it cannot check.
        result([])
        return
      }

      Task {
        var out: [[String: Any]] = []

        for await entitlement in Transaction.currentEntitlements {
          guard case .verified(let transaction) = entitlement else { continue }

          guard
            let product = try? await Product.products(for: [transaction.productID]).first,
            let subscription = product.subscription,
            let statuses = try? await subscription.status
          else { continue }

          for status in statuses {
            // Unverified renewal info is not a reason to guess. Skipped,
            // which leaves this product "unknown" to the app.
            guard case .verified(let renewal) = status.renewalInfo else { continue }

            out.append([
              "productId": transaction.productID,
              "willRenew": renewal.willAutoRenew,
              "state": Self.stateName(status.state),
            ])
          }
        }

        // Back on the platform thread. A FlutterResult called from a
        // Task continuation is otherwise off the main thread, which is
        // undefined behaviour and crashes intermittently rather than
        // reliably -- the worst way for it to be wrong.
        DispatchQueue.main.async {
          result(out)
        }
      }
    }
    // 👆 End subscription channel

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