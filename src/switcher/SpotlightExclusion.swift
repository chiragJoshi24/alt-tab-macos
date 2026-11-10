import Cocoa
import Carbon.HIToolbox.Events

/// Spotlight and the switcher are never up together: whichever was summoned last wins.
/// Detection reads the WindowServer window list, which needs no Accessibility round trip into Spotlight.
enum SpotlightExclusion {
    /// On macOS 27, ⌘-Space opens a bar owned by "Siri AI" (`com.apple.campo`); no `com.apple.Spotlight`
    /// process runs at all. Measured: closed, its bar window (layer 23) is ordered out, so it is absent from the
    /// on-screen list; open, it is on screen at layer 23. Older systems use `com.apple.Spotlight`.
    private static let bundleIds = ["com.apple.campo", "com.apple.Spotlight"]
    /// These apps also own small surfaces (a 54×54 Siri window, Spotlight's menu bar item); the bar is far larger.
    private static let minSearchBarSize = CGSize(width: 300, height: 40)
    /// Bounds a hung Siri process; the press runs off main, so this only limits how long the queue waits.
    private static let axTimeout = Float(0.5)
    private static let queue = DispatchQueue(label: "SpotlightExclusion", qos: .userInteractive)
    private static let hotkeyModifiers: CGEventFlags = [.maskCommand, .maskShift, .maskControl, .maskAlternate]

    struct Hotkey {
        let keyCode: Int64
        let modifiers: CGEventFlags
    }

    /// "Show Spotlight search" is symbolic hotkey 64. Absent from the plist means never customised: ⌘-Space.
    /// Its modifier values are the `CGEventFlags` masks. Read once; nil when the user disabled the shortcut.
    static let hotkey: Hotkey? = readHotkey()

    /// Called from the HID key-down tap while the switcher is up. Spotlight's bar fades in after it takes key
    /// focus, so the window list can't be relied on at resign-key time (measured: the switcher took focus back
    /// and the bar was left open without it). The keystroke itself is the reliable signal.
    static func isSpotlightHotkey(_ event: CGEvent) -> Bool {
        guard let hotkey else { return false }
        return event.getIntegerValueField(.keyboardEventKeycode) == hotkey.keyCode
            && event.flags.intersection(hotkeyModifiers) == hotkey.modifiers
    }

    /// Dismisses without focusing a window, like Esc, so Spotlight opens with nothing taking focus back from it.
    static func spotlightHotkeyPressed() {
        guard SwitcherSession.isActive else { return }
        App.hideUi()
    }

    private static func readHotkey() -> Hotkey? {
        let defaultHotkey = Hotkey(keyCode: Int64(kVK_Space), modifiers: .maskCommand)
        guard let hotkeys = UserDefaults(suiteName: "com.apple.symbolichotkeys")?.dictionary(forKey: "AppleSymbolicHotKeys"),
              let entry = hotkeys["64"] as? [String: Any] else { return defaultHotkey }
        guard (entry["enabled"] as? Bool) ?? true else { return nil }
        guard let value = entry["value"] as? [String: Any],
              let parameters = value["parameters"] as? [Int], parameters.count == 3 else { return defaultHotkey }
        return Hotkey(keyCode: Int64(parameters[1]), modifiers: CGEventFlags(rawValue: UInt64(parameters[2])).intersection(hotkeyModifiers))
    }

    /// The switcher lost key focus mid-session. `completion` runs on main with true when Spotlight's bar is on
    /// screen. A fallback for Spotlight opened another way (e.g. its menu bar item); ⌘-Space is caught earlier,
    /// as a keystroke, because the bar can still be off the window list when the switcher loses focus.
    static func checkIfSpotlightTookFocus(_ completion: @escaping (Bool) -> Void) {
        queue.async {
            let visible = visibleSpotlightPid() != nil
            DispatchQueue.main.async { completion(visible) }
        }
    }

    /// Measured on macOS 27: Spotlight's bar stays open under the switcher (it does not close on losing key
    /// focus), and its AX window (`AXSystemDialog`) exposes a close button, so pressing it is the bar's own close.
    static func switcherShown() {
        queue.async {
            guard let pid = visibleSpotlightPid() else { return }
            pressCloseButtons(pid)
        }
    }

    private static func pressCloseButtons(_ pid: pid_t) {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, axTimeout)
        var windows: AnyObject?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &windows) == .success else { return }
        for window in (windows as? [AXUIElement]) ?? [] {
            var closeButton: AnyObject?
            guard AXUIElementCopyAttributeValue(window, kAXCloseButtonAttribute as CFString, &closeButton) == .success,
                  let button = closeButton, CFGetTypeID(button) == AXUIElementGetTypeID() else { continue }
            AXUIElementPerformAction(button as! AXUIElement, kAXPressAction as CFString)
        }
    }

    private static func spotlightPids() -> Set<pid_t> {
        Set(bundleIds.flatMap { NSRunningApplication.runningApplications(withBundleIdentifier: $0) }.map { $0.processIdentifier })
    }

    private static func visibleSpotlightPid() -> pid_t? {
        let pids = spotlightPids()
        guard !pids.isEmpty,
              let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return nil }
        return windows.lazy.compactMap { searchBarOwner($0, pids) }.first
    }

    /// No alpha filter: Spotlight's bar can still be at alpha 0 at the start of its fade-in, which is exactly
    /// when the switcher loses key focus to it.
    private static func searchBarOwner(_ window: [String: Any], _ pids: Set<pid_t>) -> pid_t? {
        guard let owner = window[kCGWindowOwnerPID as String] as? pid_t, pids.contains(owner),
              let boundsDictionary = window[kCGWindowBounds as String] as? NSDictionary,
              let bounds = CGRect(dictionaryRepresentation: boundsDictionary),
              bounds.width >= minSearchBarSize.width, bounds.height >= minSearchBarSize.height else { return nil }
        return owner
    }
}
