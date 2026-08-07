import Common

extension Workspace {
    var tilingWindows: [Window] {
        children.filterIsInstance(of: Window.self).filter { !$0.isFloating }
    }

    var allWindows: [Window] {
        children.filterIsInstance(of: Window.self)
    }

    var floatingWindows: [Window] {
        children.filterIsInstance(of: Window.self).filter { $0.isFloating }
    }

    /// The result of applying `stack-windows-limit` to `tilingWindows`, based on the sticky
    /// `Window.isStackHidden` flags (see `enforceStackWindowsLimit`).
    struct StackLimitResolution {
        /// Master window (nil only when there are no tiling windows).
        let master: Window?
        /// Stack windows tiled on screen, in slot order.
        let visibleStack: [Window]
        /// Windows hidden off-screen because they exceed the limit.
        let hidden: [Window]
    }

    /// Reads the current split of `tilingWindows` into master, visible stack, and hidden
    /// windows from the sticky flags. Call `enforceStackWindowsLimit()` first to make the
    /// flags reflect the current window set.
    var stackLimitResolution: StackLimitResolution {
        let windows = tilingWindows
        guard let master = windows.first else { return StackLimitResolution(master: nil, visibleStack: [], hidden: []) }
        let stack = windows.dropFirst()
        return StackLimitResolution(
            master: master,
            visibleStack: stack.filter { !$0.isStackHidden },
            hidden: stack.filter { $0.isStackHidden },
        )
    }

    /// Tiling windows currently hidden off-screen by `stack-windows-limit`.
    var stackLimitHiddenWindows: [Window] { tilingWindows.dropFirst().filter { $0.isStackHidden } }

    /// Brings the flags up to date with the current window set. This is monotonic: it only
    /// hides windows (the oldest currently-visible ones once the visible stack exceeds the
    /// limit); it never reveals a hidden window. That way removing a visible window (closing,
    /// minimizing, native-hiding) does not resurface a hidden one — only an explicit focus
    /// (`revealStackWindow`) or re-adding the window does.
    @MainActor
    func enforceStackWindowsLimit() {
        var windows = tilingWindows
        guard let master = windows.first else { return }
        if config.stackWindowsLimit < 0 { // unlimited: everything is visible
            windows.forEach { $0.isStackHidden = false }
            return
        }
        // If a hidden window drifted into the master slot because the previous master was
        // removed (closed/minimized/native-hidden), promote the first *visible* stack window
        // to master instead of resurfacing the hidden one. Only when no visible stack window
        // exists (e.g. monocle) is a hidden window unavoidably promoted.
        if master.isStackHidden, let promote = windows.dropFirst().first(where: { !$0.isStackHidden }) {
            let firstTilingIndex = children.firstIndex(where: { ($0 as? Window)?.isFloating == false }) ?? 0
            promote.bind(to: self, index: firstTilingIndex)
            windows = tilingWindows
        }
        windows.first?.isStackHidden = false // the master is always visible
        let stack = Array(windows.dropFirst())
        let visible = stack.filter { !$0.isStackHidden }
        let overflow = visible.count - config.stackWindowsLimit
        guard overflow > 0 else { return }
        // Hide the oldest currently-visible windows. With `attach-below` new windows arrive at
        // the bottom, so the oldest are at the top (front); otherwise they are at the bottom (end).
        // Never hide the focused window — an explicitly focused window must stay visible.
        let focused = focus.windowOrNil
        let hidable = visible.filter { $0 != focused }
        let toHide = config.attachBelow ? hidable.prefix(overflow) : hidable.suffix(overflow)
        toHide.forEach { $0.isStackHidden = true }
    }

    /// Explicitly reveals a hidden stack window: clears its flag and moves it to the position a
    /// freshly opened window would take, so the next `enforceStackWindowsLimit()` hides the
    /// oldest *other* visible window instead. With a limit of 0 (monocle) it becomes the master.
    @MainActor
    func revealStackWindow(_ window: Window) {
        guard config.stackWindowsLimit >= 0, window.isStackHidden, window.nodeWorkspace === self else { return }
        window.isStackHidden = false
        let firstTilingIndex = children.firstIndex(where: { ($0 as? Window)?.isFloating == false }) ?? 0
        let targetIndex: Int =
            if config.stackWindowsLimit == 0 { firstTilingIndex } // become the master (monocle)
            else if config.attachBelow { INDEX_BIND_LAST } // newest visible: bottom of the stack
            else { firstTilingIndex + 1 } // newest visible: top of the stack
        window.bind(to: self, index: targetIndex)
        // Re-apply the limit right away so the just-revealed window is guaranteed to be part of
        // the visible stack (the oldest other window is hidden to make room). Doing this here,
        // rather than leaving it to the next layout pass, keeps the reveal self-consistent.
        enforceStackWindowsLimit()
    }

    /// Explicitly reveals a floating window autohidden by `center-floating-windows` on focus
    /// loss. The next layout pass recenters it (see `layoutFloatingWindow`).
    @MainActor
    func revealFloatingWindow(_ window: Window) {
        guard window.isFloatingAutoHidden, window.nodeWorkspace === self else { return }
        window.isFloatingAutoHidden = false
    }

    @MainActor var macOsNativeFullscreenWindowsContainer: MacosFullscreenWindowsContainer {
        let containers = children.filterIsInstance(of: MacosFullscreenWindowsContainer.self)
        return switch containers.count {
            case 0: MacosFullscreenWindowsContainer(parent: self)
            case 1: containers.singleOrNil().orDie()
            default: dieT("Workspace must contain zero or one MacosFullscreenWindowsContainer")
        }
    }

    @MainActor var macOsNativeHiddenAppsWindowsContainer: MacosHiddenAppsWindowsContainer {
        let containers = children.filterIsInstance(of: MacosHiddenAppsWindowsContainer.self)
        return switch containers.count {
            case 0: MacosHiddenAppsWindowsContainer(parent: self)
            case 1: containers.singleOrNil().orDie()
            default: dieT("Workspace must contain zero or one MacosHiddenAppsWindowsContainer")
        }
    }

    @MainActor var forceAssignedMonitor: Monitor? {
        guard let monitorDescriptions = config.workspaceToMonitorForceAssignment[name] else { return nil }
        let sortedMonitors = sortedMonitors
        return monitorDescriptions.lazy
            .compactMap { $0.resolveMonitor(sortedMonitors: sortedMonitors) }
            .first
    }
}
