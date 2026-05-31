// ios/Runner/SceneDelegate.swift
//
// UISceneDelegate for CrispCloud.
//
// Required by the UIApplicationSceneManifest entry in Info.plist that enables
// Stage Manager / multi-window support on iPadOS 13+.
//
// Responsibilities
// ─────────────────
// 1. Initialise Flutter for each scene (window) independently.
// 2. Forward UIScene lifecycle events to Flutter via the
//    "com.crispcloud/multi_window" MethodChannel so that Dart-side
//    MultiWindowService can track open windows.
// 3. Handle NSUserActivity (Siri shortcuts, Handoff, Spotlight) and route
//    them to the appropriate Flutter service via their respective channels.
//
// One SceneDelegate instance is created per window.  Flutter shares one
// engine (managed by AppDelegate.flutterEngine) across all scenes.

import UIKit
import Flutter
import Intents

@available(iOS 13.0, *)
class SceneDelegate: UIResponder, UIWindowSceneDelegate {

    var window: UIWindow?

    // MethodChannels for this scene's Flutter view controller.
    private var multiWindowChannel: FlutterMethodChannel?
    private var siriChannel: FlutterMethodChannel?
    private var shareExtChannel: FlutterMethodChannel?

    // MARK: - Scene lifecycle

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let windowScene = scene as? UIWindowScene else { return }

        // Re-use the shared Flutter engine set up in AppDelegate so all
        // scenes share one Dart isolate.
        let engine = (UIApplication.shared.delegate as? AppDelegate)?.flutterEngine
            ?? FlutterEngine(name: "scene_engine_\(session.persistentIdentifier)")

        let controller = FlutterViewController(engine: engine, nibName: nil, bundle: nil)

        let newWindow = UIWindow(windowScene: windowScene)
        newWindow.rootViewController = controller
        newWindow.makeKeyAndVisible()
        self.window = newWindow

        setupChannels(messenger: controller.binaryMessenger,
                      sceneId: session.persistentIdentifier)

        notifyWindowStateChanged()

        // Handle any activity that triggered this scene connection (e.g. Siri shortcut).
        if let activity = connectionOptions.userActivities.first {
            handleUserActivity(activity)
        }

        NSLog("[CrispCloud] Scene connected: \(session.persistentIdentifier)")
    }

    func sceneDidDisconnect(_ scene: UIScene) {
        NSLog("[CrispCloud] Scene disconnected")
        notifyWindowStateChanged()
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        NSLog("[CrispCloud] Scene became active")
        notifyWindowStateChanged()
    }

    func sceneWillResignActive(_ scene: UIScene) {
        NSLog("[CrispCloud] Scene will resign active")
    }

    func scene(_ scene: UIScene, continue userActivity: NSUserActivity) {
        handleUserActivity(userActivity)
    }

    // MARK: - Channel setup

    private func setupChannels(messenger: FlutterBinaryMessenger, sceneId: String) {
        // Multi-window channel
        multiWindowChannel = FlutterMethodChannel(
            name: "com.crispcloud/multi_window",
            binaryMessenger: messenger
        )
        multiWindowChannel?.setMethodCallHandler { [weak self] call, result in
            self?.handleMultiWindowCall(call, result: result, sceneId: sceneId)
        }

        // Siri shortcuts channel
        siriChannel = FlutterMethodChannel(
            name: "com.crispcloud/siri_shortcuts",
            binaryMessenger: messenger
        )
        siriChannel?.setMethodCallHandler { [weak self] call, result in
            self?.handleSiriCall(call, result: result)
        }

        // Share extension channel
        shareExtChannel = FlutterMethodChannel(
            name: "com.crispcloud/share_extension",
            binaryMessenger: messenger
        )
        shareExtChannel?.setMethodCallHandler { [weak self] call, result in
            self?.handleShareExtensionCall(call, result: result)
        }
    }

    // MARK: - Multi-window channel handler

    private func handleMultiWindowCall(
        _ call: FlutterMethodCall,
        result: @escaping FlutterResult,
        sceneId: String
    ) {
        switch call.method {

        case "getWindowState":
            result(buildWindowStateDict(currentSceneId: sceneId))

        case "requestNewWindow":
            let label = (call.arguments as? [String: Any])?["label"] as? String ?? "CrispCloud"
            requestNewScene(label: label, result: result)

        case "closeWindow":
            if let targetId = (call.arguments as? [String: Any])?["sceneId"] as? String {
                closeScene(withId: targetId)
            }
            result(nil)

        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // MARK: - Siri shortcuts channel handler

    private func handleSiriCall(
        _ call: FlutterMethodCall,
        result: @escaping FlutterResult
    ) {
        switch call.method {

        case "registerShortcuts":
            guard let args      = call.arguments as? [String: Any],
                  let shortcuts = args["shortcuts"] as? [[String: String]]
            else {
                result(FlutterError(code: "INVALID_ARGS",
                                    message: "Expected shortcuts array",
                                    details: nil))
                return
            }
            doRegisterShortcuts(shortcuts)
            result(nil)

        case "donateShortcut":
            if let shortcut = call.arguments as? [String: String] {
                doDonateShortcut(shortcut)
            }
            result(nil)

        case "removeAllShortcuts":
            if #available(iOS 12.0, *) {
                INVoiceShortcutCenter.shared.getAllVoiceShortcuts { shortcuts, _ in
                    shortcuts?.forEach { vs in
                        INVoiceShortcutCenter.shared.deleteVoiceShortcut(
                            withIdentifier: vs.identifier) { _, _ in }
                    }
                }
            }
            result(nil)

        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // MARK: - Share extension channel handler

    private func handleShareExtensionCall(
        _ call: FlutterMethodCall,
        result: @escaping FlutterResult
    ) {
        let defaults   = UserDefaults(suiteName: SharedDefaults.appGroupIdentifier)
        let pendingKey = "cc_pending_uploads"

        switch call.method {

        case "readPendingUploads":
            guard let data = defaults?.data(forKey: pendingKey),
                  let json = String(data: data, encoding: .utf8)
            else {
                result("[]")
                return
            }
            result(json)

        case "writePendingUploads":
            guard let args = call.arguments as? [String: Any],
                  let json = args["json"] as? String,
                  let data = json.data(using: .utf8)
            else {
                result(FlutterError(code: "INVALID_ARGS",
                                    message: "Expected 'json' string",
                                    details: nil))
                return
            }
            defaults?.set(data, forKey: pendingKey)
            result(nil)

        case "deleteShareInboxFile":
            if let args = call.arguments as? [String: Any],
               let path = args["path"] as? String {
                try? FileManager.default.removeItem(atPath: path)
                NSLog("[CrispCloud] Deleted inbox file: \(path)")
            }
            result(nil)

        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // MARK: - User activity / Siri shortcut routing

    private func handleUserActivity(_ activity: NSUserActivity) {
        NSLog("[CrispCloud] Handling user activity: \(activity.activityType)")
        siriChannel?.invokeMethod("shortcutActivated", arguments: activity.activityType)
    }

    // MARK: - Multi-window helpers

    private func buildWindowStateDict(currentSceneId: String) -> [String: Any] {
        let sessions = UIApplication.shared.openSessions
        let windows: [[String: String]] = sessions.map { session in
            [
                "sceneId": session.persistentIdentifier,
                "label":   session.configuration.name ?? "CrispCloud",
            ]
        }
        return [
            "isCapable":      UIApplication.shared.supportsMultipleScenes,
            "currentSceneId": currentSceneId,
            "openWindows":    windows,
        ]
    }

    private func requestNewScene(label: String, result: @escaping FlutterResult) {
        let options  = UIWindowScene.ActivationRequestOptions()
        let activity = NSUserActivity(activityType: "com.crispcloud.newwindow")
        activity.title = label

        UIApplication.shared.requestSceneSessionActivation(
            nil,
            userActivity: activity,
            options: options
        ) { error in
            if let error = error {
                NSLog("[CrispCloud] requestSceneSessionActivation error: \(error.localizedDescription)")
                result(false)
            } else {
                result(true)
            }
        }
    }

    private func closeScene(withId sceneId: String) {
        guard let session = UIApplication.shared.openSessions.first(
            where: { $0.persistentIdentifier == sceneId }
        ) else { return }
        UIApplication.shared.requestSceneSessionDestruction(
            session, options: nil, errorHandler: nil)
    }

    private func notifyWindowStateChanged() {
        let sessions = UIApplication.shared.openSessions
        let windows: [[String: String]] = sessions.map { session in
            ["sceneId": session.persistentIdentifier,
             "label":   session.configuration.name ?? "CrispCloud"]
        }
        let state: [String: Any] = [
            "isCapable":      UIApplication.shared.supportsMultipleScenes,
            "currentSceneId": window?.windowScene?.session.persistentIdentifier ?? "",
            "openWindows":    windows,
        ]
        multiWindowChannel?.invokeMethod("windowStateChanged", arguments: state)
    }

    // MARK: - Siri shortcut helpers

    /// Register (donate) all shortcuts.  Uses INInteraction on iOS 12+.
    private func doRegisterShortcuts(_ shortcuts: [[String: String]]) {
        guard #available(iOS 12.0, *) else {
            NSLog("[CrispCloud] Siri shortcuts require iOS 12+")
            return
        }
        for shortcut in shortcuts {
            guard let identifier = shortcut["identifier"],
                  let title      = shortcut["title"],
                  let phrase     = shortcut["suggestedInvocationPhrase"]
            else { continue }

            let activity           = NSUserActivity(activityType: identifier)
            activity.title         = title
            activity.isEligibleForSearch      = true
            activity.isEligibleForPrediction  = true
            activity.suggestedInvocationPhrase = phrase

            let inShortcut  = INShortcut(userActivity: activity)
            let interaction = INInteraction(intent: inShortcut.intent ?? INIntent(),
                                            response: nil)
            interaction.donate { error in
                if let error = error {
                    NSLog("[CrispCloud] Shortcut donation error (\(identifier)): \(error.localizedDescription)")
                } else {
                    NSLog("[CrispCloud] Shortcut donated: \(identifier)")
                }
            }
        }
    }

    /// Donate a single shortcut interaction to improve Siri suggestion ranking.
    private func doDonateShortcut(_ shortcut: [String: String]) {
        guard #available(iOS 12.0, *),
              let identifier = shortcut["identifier"],
              let title      = shortcut["title"]
        else { return }

        let activity           = NSUserActivity(activityType: identifier)
        activity.title         = title
        activity.isEligibleForSearch      = true
        activity.isEligibleForPrediction  = true
        if let phrase = shortcut["suggestedInvocationPhrase"] {
            activity.suggestedInvocationPhrase = phrase
        }
        let inShortcut  = INShortcut(userActivity: activity)
        let interaction = INInteraction(intent: inShortcut.intent ?? INIntent(),
                                        response: nil)
        interaction.donate(completion: nil)
    }
}
