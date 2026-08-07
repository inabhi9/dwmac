@MainActor private var lastKnownNativeFocusedWindowId: UInt32? = nil

/// The window ID that we told macOS to focus via nativeFocus() but that macOS may not have
/// processed yet. While this is set, updateFocusCache will not overwrite _focus with a stale
/// native-focused window — it will only clear the expectation once macOS confirms the target.
@MainActor private var expectedNativeFocusWindowId: UInt32? = nil

/// The window we were focused on *before* calling nativeFocus(). While the expectation is
/// pending, this is the only native focus value we treat as "stale" (i.e. macOS hasn't caught
/// up yet). Any *other* native focus — e.g. a newly opened app — is a genuine focus change and
/// must be honored, otherwise the expectation would get stuck and dwmac would keep showing the
/// old window as focused.
@MainActor private var staleNativeFocusWindowId: UInt32? = nil

/// Call after nativeFocus() to prevent racing refresh sessions from overwriting _focus
/// with stale native focus before macOS has processed the activation. `staleValue` is the
/// window we're switching away from (the only value that means "macOS hasn't caught up yet").
@MainActor func markNativeFocusExpected(_ window: Window?, staleValue: Window? = nil) {
    expectedNativeFocusWindowId = window?.windowId
    staleNativeFocusWindowId = staleValue?.windowId
}

/// The data should flow (from nativeFocused to focused) and
///                      (from nativeFocused to lastKnownNativeFocusedWindowId)
/// Alternative names: takeFocusFromMacOs, syncFocusFromMacOs
@MainActor func updateFocusCache(_ nativeFocused: Window?) {
    if nativeFocused?.parent is MacosPopupWindowsContainer {
        return
    }
    if let expected = expectedNativeFocusWindowId, let nativeId = nativeFocused?.windowId {
        if nativeId == expected {
            // macOS caught up — clear the expectation and proceed normally
            expectedNativeFocusWindowId = nil
            staleNativeFocusWindowId = nil
        } else if nativeId == staleNativeFocusWindowId {
            // Still seeing the window we're switching away from — macOS hasn't processed our
            // nativeFocus() yet. Don't overwrite _focus, but keep lastNativeFocusedWindowId fresh.
            lastKnownNativeFocusedWindowId = nativeId
            nativeFocused?.macAppUnsafe.lastNativeFocusedWindowId = nativeId
            return
        } else {
            // A different window became natively focused (e.g. a newly opened app). This is a
            // genuine focus change, not the stale pre-nativeFocus() state — honor it and drop
            // the pending expectation so we don't get stuck showing the old window as focused.
            expectedNativeFocusWindowId = nil
            staleNativeFocusWindowId = nil
        }
    }
    if nativeFocused?.windowId != lastKnownNativeFocusedWindowId {
        // focusWindow() returns false when the window isn't focusable *yet* — e.g. a window that
        // was just unminimized is still parked in macosMinimizedWindowsContainer (visualWorkspace
        // == nil) at this point in the refresh; normalizeLayoutReason() moves it back into the
        // workspace only later. Don't cache lastKnownNativeFocusedWindowId in that case, otherwise
        // the guard above would suppress the retry and _focus would stay on the old window forever.
        // Leaving it unset lets the next refresh (triggered by the relayout's move/resize) refocus.
        if nativeFocused?.focusWindow() != false {
            lastKnownNativeFocusedWindowId = nativeFocused?.windowId
        }
    }
    nativeFocused?.macAppUnsafe.lastNativeFocusedWindowId = nativeFocused?.windowId
}
