import AppKit
import Common

enum EffectiveLeaf {
    case window(Window)
    case emptyWorkspace(Workspace)
}
extension LiveFocus {
    var asLeaf: EffectiveLeaf {
        if let windowOrNil { .window(windowOrNil) } else { .emptyWorkspace(workspace) }
    }
}

/// This object should be only passed around but never memorized
/// Alternative name: ResolvedFocus
struct LiveFocus: AeroAny, Equatable {
    let windowOrNil: Window?
    var workspace: Workspace

    @MainActor var frozen: FrozenFocus {
        return FrozenFocus(
            windowId: windowOrNil?.windowId,
            workspaceName: workspace.name,
            monitorId: workspace.workspaceMonitor.monitorId ?? 0,
        )
    }
}

/// "old", "captured", "frozen in time" Focus
/// It's safe to keep a hard reference to this object.
/// Unlike in LiveFocus, information inside FrozenFocus isn't guaranteed to be self-consistent.
/// window - workspace - monitor relation could change since the object is created
struct FrozenFocus: AeroAny, Equatable, Sendable {
    let windowId: UInt32?
    let workspaceName: String
    // monitorId is not part of the focus. We keep it here only for 'on-monitor-changed' to work
    let monitorId: Int // 0-based

    @MainActor var live: LiveFocus { // Important: don't access focus.monitorId here. monitorId is not part of the focus. Always prefer workspace
        let window: Window? = windowId.flatMap { Window.get(byId: $0) }
        let workspace = Workspace.get(byName: workspaceName)

        let wsFocus = workspace.toLiveFocus()
        let wdFocus = window?.toLiveFocusOrNil() ?? wsFocus

        return wsFocus.workspace != wdFocus.workspace
            ? wsFocus // If window and workspace become separated prefer workspace
            : wdFocus
    }
}

@MainActor private var _focus: FrozenFocus = {
    let monitor = mainMonitor
    return FrozenFocus(windowId: nil, workspaceName: monitor.activeWorkspace.name, monitorId: monitor.monitorId ?? 0)
}()

/// Global focus.
/// Commands must be cautious about accessing this property directly. There are legitimate cases.
/// But, in general, commands must firstly check --window-id, --workspace, DWMAC_WINDOW_ID env and
/// DWMAC_WORKSPACE env before accessing the global focus.
@MainActor var focus: LiveFocus { _focus.live }

@MainActor func setFocus(to newFocus: LiveFocus) -> Bool {
    if _focus == newFocus.frozen { return true }
    let oldFocus = focus
    // Normalize mruWindow when focus away from a workspace
    if oldFocus.workspace != newFocus.workspace {
        oldFocus.windowOrNil?.markAsMostRecentChild()
    }

    _focus = newFocus.frozen
    let status = newFocus.workspace.workspaceMonitor.setActiveWorkspace(newFocus.workspace)

    newFocus.windowOrNil?.markAsMostRecentChild()
    return status
}
extension Window {
    @MainActor func focusWindow() -> Bool {
        guard let liveFocus = toLiveFocusOrNil() else {
            // todo We should also exit-native-hidden/unminimize[/exit-native-fullscreen?] window if we want to fix ID-B6E178F2
            //      and retry to focus the window. Otherwise, it's not possible to focus minimized/hidden windows
            return false
        }
        let result = setFocus(to: liveFocus)
        // Explicitly focusing a window hidden by `stack-windows-limit` brings it into view.
        // This runs *after* setFocus so the window counts as focused while `revealStackWindow`
        // re-applies the limit (the focused window is never hidden). Incidental focus
        // reassignment, e.g. on window close, goes through `setFocus` directly and does not reveal.
        if !isFloating {
            nodeWorkspace?.revealStackWindow(self)
        } else {
            nodeWorkspace?.revealFloatingWindow(self)
        }
        return result
    }

    @MainActor func toLiveFocusOrNil() -> LiveFocus? { visualWorkspace.map { LiveFocus(windowOrNil: self, workspace: $0) } }
}
extension Workspace {
    @MainActor func focusWorkspace() -> Bool { setFocus(to: toLiveFocus()) }

    func toLiveFocus() -> LiveFocus {
        // todo unfortunately mostRecentWindowRecursive may recursively reach empty rootTilingContainer
        //      while floating or macos unconventional windows might be presented
        // Prefer a visible window: don't resurface a window hidden by `stack-windows-limit`
        // just because the previously focused window went away.
        let hidden = Set(tilingWindows.dropFirst().filter { $0.isStackHidden })
        let preferred = mostRecentWindowRecursive.flatMap { hidden.contains($0) ? nil : $0 }
            ?? allWindows.first { !hidden.contains($0) }
        return if let wd = preferred ?? mostRecentWindowRecursive ?? anyLeafWindowRecursive {
            LiveFocus(windowOrNil: wd, workspace: self)
        } else {
            LiveFocus(windowOrNil: nil, workspace: self) // emptyWorkspace
        }
    }
}

@MainActor private var _lastKnownFocus: FrozenFocus = _focus

// Used by workspace-back-and-forth
@MainActor var _prevFocusedWorkspaceName: String? = nil {
    didSet {
        prevFocusedWorkspaceDate = .now
    }
}
@MainActor var prevFocusedWorkspaceDate: Date = .distantPast
@MainActor var prevFocusedWorkspace: Workspace? { _prevFocusedWorkspaceName.map { Workspace.get(byName: $0) } }

// Used by focus-back-and-forth
@MainActor var _prevFocus: FrozenFocus? = nil
@MainActor var prevFocus: LiveFocus? { _prevFocus?.live.takeIf { $0 != focus } }

@MainActor private var onFocusChangedRecursionGuard = false
// Should be called in refreshSession
@MainActor func checkOnFocusChangedCallbacks() {
    if refreshSessionEvent?.isStartup == true {
        return
    }
    let focus = focus
    let frozenFocus = focus.frozen
    var hasFocusChanged = false
    var hasFocusedWorkspaceChanged = false
    var hasFocusedMonitorChanged = false
    if frozenFocus != _lastKnownFocus {
        updateFloatingAutoHide(oldFocus: _lastKnownFocus, newFocus: focus)
        _prevFocus = _lastKnownFocus
        hasFocusChanged = true
    }
    if frozenFocus.workspaceName != _lastKnownFocus.workspaceName {
        _prevFocusedWorkspaceName = _lastKnownFocus.workspaceName
        hasFocusedWorkspaceChanged = true
    }
    if frozenFocus.monitorId != _lastKnownFocus.monitorId {
        hasFocusedMonitorChanged = true
    }
    _lastKnownFocus = frozenFocus

    if onFocusChangedRecursionGuard { return }
    onFocusChangedRecursionGuard = true
    defer { onFocusChangedRecursionGuard = false }
    if hasFocusChanged {
        onFocusChanged(focus)
    }
    if let _prevFocusedWorkspaceName, hasFocusedWorkspaceChanged {
        onWorkspaceChanged(_prevFocusedWorkspaceName, frozenFocus.workspaceName)
    }
    if hasFocusedMonitorChanged {
        onFocusedMonitorChanged(focus)
    }
}

/// `center-floating-windows` autohide: when focus moves away from a floating window, mark it
/// autohidden so the next layout pass moves it off-screen (see `layoutFloatingWindow`). Only
/// the window that actually lost focus is touched — never other floating windows.
@MainActor private func updateFloatingAutoHide(oldFocus: FrozenFocus, newFocus: LiveFocus) {
    guard config.centerFloatingWindows else { return }
    guard let oldWindow = oldFocus.live.windowOrNil, oldWindow.isFloating else { return }
    guard oldWindow != newFocus.windowOrNil else { return }
    guard oldWindow.layoutReason == .standard else { return } // already minimized/fullscreen/macos-hidden — leave to that subsystem
    oldWindow.isFloatingAutoHidden = true
}

@MainActor private func onFocusedMonitorChanged(_ focus: LiveFocus) {
    if config.onFocusedMonitorChanged.isEmpty { return }
    guard let token: RunSessionGuard = .isServerEnabled else { return }
    // todo potential optimization: don't run runSession if we are already in runSession
    Task {
        try await runLightSession(.onFocusedMonitorChanged, token) {
            _ = try await config.onFocusedMonitorChanged.runCmdSeq(.defaultEnv.withFocus(focus), .emptyStdin)
        }
    }
}
@MainActor private func onFocusChanged(_ focus: LiveFocus) {
    if config.onFocusChanged.isEmpty { return }
    guard let token: RunSessionGuard = .isServerEnabled else { return }
    // todo potential optimization: don't run runSession if we are already in runSession
    Task {
        try await runLightSession(.onFocusChanged, token) {
            _ = try await config.onFocusChanged.runCmdSeq(.defaultEnv.withFocus(focus), .emptyStdin)
        }
    }
}

@MainActor private func onWorkspaceChanged(_ oldWorkspace: String, _ newWorkspace: String) {
    if let exec = config.execOnWorkspaceChange.first {
        let process = Process()
        process.executableURL = URL(filePath: exec)
        process.arguments = Array(config.execOnWorkspaceChange.dropFirst())
        var environment = config.execConfig.envVariables
        environment["DWMAC_FOCUSED_WORKSPACE"] = newWorkspace
        environment["DWMAC_PREV_WORKSPACE"] = oldWorkspace
        environment[DWMAC_WORKSPACE] = newWorkspace
        process.environment = environment
        _ = Result { try process.run() }
    }
}
