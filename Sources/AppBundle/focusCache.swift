@MainActor private var lastKnownNativeFocusedWindowId: UInt32? = nil

/// The window ID that we told macOS to focus via nativeFocus() but that macOS may not have
/// processed yet. While this is set, updateFocusCache will not overwrite _focus with a stale
/// native-focused window — it will only clear the expectation once macOS confirms the target.
@MainActor private var expectedNativeFocusWindowId: UInt32? = nil

/// Call after nativeFocus() to prevent racing refresh sessions from overwriting _focus
/// with stale native focus before macOS has processed the activation.
@MainActor func markNativeFocusExpected(_ window: Window?) {
    expectedNativeFocusWindowId = window?.windowId
}

/// The data should flow (from nativeFocused to focused) and
///                      (from nativeFocused to lastKnownNativeFocusedWindowId)
/// Alternative names: takeFocusFromMacOs, syncFocusFromMacOs
@MainActor func updateFocusCache(_ nativeFocused: Window?) {
    if nativeFocused?.parent is MacosPopupWindowsContainer {
        return
    }
    if let expected = expectedNativeFocusWindowId {
        if nativeFocused?.windowId == expected {
            // macOS caught up — clear the expectation and proceed normally
            expectedNativeFocusWindowId = nil
        } else {
            // macOS hasn't processed our nativeFocus() yet — don't overwrite _focus
            // but still update lastNativeFocusedWindowId for the app
            lastKnownNativeFocusedWindowId = nativeFocused?.windowId
            nativeFocused?.macAppUnsafe.lastNativeFocusedWindowId = nativeFocused?.windowId
            return
        }
    }
    if nativeFocused?.windowId != lastKnownNativeFocusedWindowId {
        _ = nativeFocused?.focusWindow()
        lastKnownNativeFocusedWindowId = nativeFocused?.windowId
    }
    nativeFocused?.macAppUnsafe.lastNativeFocusedWindowId = nativeFocused?.windowId
}
