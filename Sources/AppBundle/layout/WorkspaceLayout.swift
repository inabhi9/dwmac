import AppKit

extension Workspace {
    @MainActor
    func layoutWorkspace(hideCorner: OptimalHideCorner = .bottomRightCorner) async throws {
        if isEffectivelyEmpty { return }
        let rect = workspaceMonitor.visibleRectPaddedByOuterGaps
        let context = LayoutContext(self)

        // Layout tiling windows
        try await layoutMasterStack(rect.topLeftCorner, width: rect.width, height: rect.height - 1, virtual: rect, hideCorner: hideCorner, context)

        // Layout floating windows
        for window in children.filterIsInstance(of: Window.self).filter({ $0.isFloating }) {
            window.lastAppliedLayoutPhysicalRect = nil
            window.lastAppliedLayoutVirtualRect = nil
            try await window.layoutFloatingWindow(context)
        }
    }

    @MainActor
    private func layoutMasterStack(_ point: CGPoint, width: CGFloat, height: CGFloat, virtual: Rect, hideCorner: OptimalHideCorner, _ context: LayoutContext) async throws {
        if tilingWindows.isEmpty { return }

        if layout == .floating {
            return
        }

        // Bring the sticky hidden flags up to date with the current window set (only ever hides
        // the oldest overflowing windows; never resurfaces a hidden one).
        enforceStackWindowsLimit()

        let resolved = stackLimitResolution
        guard let master = resolved.master else { return }

        let gaps = context.resolvedGaps.inner
        let gapH = CGFloat(gaps.horizontal)
        let gapV = CGFloat(gaps.vertical)

        // Monocle case: no stack is tiled (either there is a single window, or the stack
        // limit is 0). The master fills the whole area and every other window is removed
        // from the layout and hidden off-screen.
        if resolved.visibleStack.isEmpty {
            try await layoutWindow(master, point, width, height, virtual, context)
            for window in resolved.hidden {
                try await window.hideInCorner(hideCorner)
            }
            return
        }

        let visibleStackCount = resolved.visibleStack.count
        let masterWidth: CGFloat
        let masterHeight: CGFloat
        let stackWidth: CGFloat
        let stackHeight: CGFloat

        if orientation == .h {
            masterWidth = (width - gapH) * mfact
            masterHeight = height
            stackWidth = width - masterWidth - gapH
            stackHeight = (height - CGFloat(visibleStackCount - 1) * gapV) / CGFloat(visibleStackCount)
        } else {
            masterWidth = width
            masterHeight = (height - gapV) * mfact
            stackWidth = (width - CGFloat(visibleStackCount - 1) * gapH) / CGFloat(visibleStackCount)
            stackHeight = height - masterHeight - gapV
        }

        let masterOrigin: CGPoint
        let stackOrigin: CGPoint

        if orientation == .h {
            if config.masterPosition == .right {
                masterOrigin = point.addingXOffset(stackWidth + gapH)
                stackOrigin = point
            } else {
                masterOrigin = point
                stackOrigin = point.addingXOffset(masterWidth + gapH)
            }
        } else {
            masterOrigin = point
            stackOrigin = point.addingYOffset(masterHeight + gapV)
        }

        func stackSlotPoint(_ slot: Int) -> CGPoint {
            orientation == .h
                ? stackOrigin.addingYOffset(CGFloat(slot) * (stackHeight + gapV))
                : stackOrigin.addingXOffset(CGFloat(slot) * (stackWidth + gapH))
        }

        // Master window (first in list)
        try await layoutWindow(master, masterOrigin, masterWidth, masterHeight, virtual, context)

        // Visible stack windows (up to the configured limit)
        for (slot, window) in resolved.visibleStack.enumerated() {
            try await layoutWindow(window, stackSlotPoint(slot), stackWidth, stackHeight, virtual, context)
        }

        // Windows beyond the limit are hidden off-screen instead of covering a tiled window.
        for window in resolved.hidden {
            try await window.hideInCorner(hideCorner)
        }
    }

    @MainActor
    private func layoutWindow(_ window: Window, _ point: CGPoint, _ width: CGFloat, _ height: CGFloat, _ virtual: Rect, _ context: LayoutContext) async throws {
        let physicalRect = Rect(topLeftX: point.x, topLeftY: point.y, width: width, height: height)

        if window.windowId != currentlyManipulatedWithMouseWindowId {
            window.lastAppliedLayoutVirtualRect = virtual
            // In flat model, no rootTilingContainer. Check if window is fullscreen and matches criteria.
            // Assuming mostRecentWindowRecursive logic works on Workspace now.
            if window.isFullscreen && window == context.workspace.mostRecentWindowRecursive {
                window.lastAppliedLayoutPhysicalRect = nil
                window.layoutFullscreen(context)
            } else {
                window.lastAppliedLayoutPhysicalRect = physicalRect
                window.isFullscreen = false
                window.setAxFrame(point, CGSize(width: width, height: height))
            }
        }
    }
}

private struct LayoutContext {
    let workspace: Workspace
    let resolvedGaps: ResolvedGaps

    @MainActor
    init(_ workspace: Workspace) {
        self.workspace = workspace
        self.resolvedGaps = ResolvedGaps(gaps: config.gaps, monitor: workspace.workspaceMonitor)
    }
}

extension Window {
    @MainActor
    fileprivate func layoutFloatingWindow(_ context: LayoutContext) async throws {
        let workspace = context.workspace
        let targetMonitor = workspace.workspaceMonitor

        if config.centerFloatingWindows && windowId != currentlyManipulatedWithMouseWindowId {
            if let windowSize = try await getAxSize() ?? lastFloatingSize {
                let monitorRect = targetMonitor.visibleRect
                let topLeft = CGPoint(
                    x: monitorRect.topLeftX + (monitorRect.width - windowSize.width) / 2,
                    y: monitorRect.topLeftY + (monitorRect.height - windowSize.height) / 2
                )
                setAxFrame(topLeft, nil)
            }
        } else {
            // Optimization: Only check for monitor drift if the workspace's monitor has changed
            // since the last layout of this window.
            // This avoids expensive AX calls (getCenter/getAxTopLeftCorner) on every layout cycle.
            if lastLayoutMonitor?.rect.topLeftCorner != targetMonitor.rect.topLeftCorner {
                let currentMonitor = try await getCenter()?.monitorApproximation
                if let currentMonitor, let windowTopLeftCorner = try await getAxTopLeftCorner(), workspace != currentMonitor.activeWorkspace {
                    let xProportion = (windowTopLeftCorner.x - currentMonitor.visibleRect.topLeftX) / currentMonitor.visibleRect.width
                    let yProportion = (windowTopLeftCorner.y - currentMonitor.visibleRect.topLeftY) / currentMonitor.visibleRect.height

                    let moveTo = workspace.workspaceMonitor
                    setAxFrame(CGPoint(
                        x: moveTo.visibleRect.topLeftX + xProportion * moveTo.visibleRect.width,
                        y: moveTo.visibleRect.topLeftY + yProportion * moveTo.visibleRect.height,
                    ), nil)
                }
            }
        }
        lastLayoutMonitor = targetMonitor

        if isFullscreen {
            layoutFullscreen(context)
            isFullscreen = false
        }
    }

    @MainActor
    fileprivate func layoutFullscreen(_ context: LayoutContext) {
        let monitorRect = noOuterGapsInFullscreen
            ? context.workspace.workspaceMonitor.visibleRect
            : context.workspace.workspaceMonitor.visibleRectPaddedByOuterGaps
        setAxFrame(monitorRect.topLeftCorner, CGSize(width: monitorRect.width, height: monitorRect.height))
    }
}
