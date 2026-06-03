//
//  AppDelegate.swift
//  Lumen
//
//  A minimal AppKit delegate, attached to the SwiftUI `App` via
//  `NSApplicationDelegateAdaptor`, that keeps the app alive across the brief
//  window-less window during AppKit state restoration on relaunch.
//
//  Why this exists (Phase-2 relaunch regression, lumen-cle):
//  Lumen uses a SINGLE `Window(id: "main")` scene. When the app is relaunched
//  after a previous `terminate:` (e.g. the P1.21 UI test's relaunch, or a user
//  quitting and reopening), AppKit runs window state restoration. During that
//  dance the app momentarily reports "No windows open yet". Because a modern
//  Cocoa app supports *automatic* and *sudden* termination by default, macOS
//  could reap the process in that gap — the app would exit via a graceful
//  `terminate:` (no crash report) BEFORE the restored window/editor appeared.
//  Symptom: intermittent "Application 'ai.Lumen' is not running" in the UI
//  test, and the user's "press ▶ Run, nothing happens" when saved state exists.
//
//  Disabling automatic + sudden termination closes that window: the process is
//  guaranteed to stay alive until it is explicitly asked to quit, so the single
//  restored window always gets a chance to materialize.
//

import AppKit

/// Keeps the single-window app from being auto-reaped during state restoration.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        let process = ProcessInfo.processInfo
        // Hold an automatic-termination assertion for the whole app lifetime:
        // the app owns one persistent main window and must not be reaped while
        // that window is briefly absent during relaunch state restoration.
        process.disableAutomaticTermination("Lumen keeps a single main window")
        // Sudden termination would let the system kill us without running the
        // normal terminate path during the same restoration gap; opt out so the
        // process survives until an explicit quit.
        process.disableSuddenTermination()
    }

    /// The app is single-window and document-less; closing the window should
    /// not quit the app (the window is restored on next launch).
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// Opt into secure state restoration (required on modern macOS; silences the
    /// AppKit warning and keeps restoration on the supported path).
    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }
}
