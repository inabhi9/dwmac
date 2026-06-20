import AppKit
import Common

private struct MonitorImpl {
    let monitorAppKitNsScreenScreensId: Int
    let name: String
    let rect: Rect
    let visibleRect: Rect
    let isMain: Bool
}

extension MonitorImpl: Monitor {
    var height: CGFloat { rect.height }
    var width: CGFloat { rect.width }
}

/// A virtual monitor that spans the bounding box of multiple physical monitors.
/// Used when ``Config/treatMultipleMonitorsAsOne`` is enabled so that a single
/// workspace can extend across all attached displays.
private struct CombinedMonitor: Monitor {
    let monitorAppKitNsScreenScreensId: Int
    let name: String
    let rect: Rect
    let visibleRect: Rect
    let isMain: Bool
    var height: CGFloat { rect.height }
    var width: CGFloat { rect.width }
}

private func combineMonitors(_ underlying: [Monitor]) -> Monitor? {
    guard let first = underlying.first else { return nil }
    if underlying.count == 1 { return first }

    func boundingBox(_ rects: [Rect]) -> Rect {
        let minX = rects.map(\.minX).min() ?? 0
        let minY = rects.map(\.minY).min() ?? 0
        let maxX = rects.map(\.maxX).max() ?? 0
        let maxY = rects.map(\.maxY).max() ?? 0
        return Rect(topLeftX: minX, topLeftY: minY, width: maxX - minX, height: maxY - minY)
    }

    let rect = boundingBox(underlying.map(\.rect))
    let visibleRect = boundingBox(underlying.map(\.visibleRect))
    let mainId = underlying.first(where: \.isMain)?.monitorAppKitNsScreenScreensId
        ?? first.monitorAppKitNsScreenScreensId
    let name = "Combined (\(underlying.map(\.name).joined(separator: ", ")))"

    return CombinedMonitor(
        monitorAppKitNsScreenScreensId: mainId,
        name: name,
        rect: rect,
        visibleRect: visibleRect,
        isMain: true,
    )
}

/// Use it instead of NSScreen because it can be mocked in tests
protocol Monitor: AeroAny {
    /// The index in NSScreen.screens array. 1-based index
    var monitorAppKitNsScreenScreensId: Int { get }
    var name: String { get }
    var rect: Rect { get }
    var visibleRect: Rect { get }
    var width: CGFloat { get }
    var height: CGFloat { get }
    var isMain: Bool { get }
}

final class LazyMonitor: Monitor {
    private let screen: NSScreen
    let monitorAppKitNsScreenScreensId: Int
    let name: String
    let width: CGFloat
    let height: CGFloat
    let isMain: Bool
    private var _rect: Rect?
    private var _visibleRect: Rect?

    init(monitorAppKitNsScreenScreensId: Int, isMain: Bool, _ screen: NSScreen) {
        self.monitorAppKitNsScreenScreensId = monitorAppKitNsScreenScreensId
        self.name = screen.localizedName
        self.width = screen.frame.width // Don't call rect because it would cause recursion during mainMonitor init
        self.height = screen.frame.height // Don't call rect because it would cause recursion during mainMonitor init
        self.screen = screen
        self.isMain = isMain
    }

    var rect: Rect {
        _rect ?? screen.rect.also { _rect = $0 }
    }

    var visibleRect: Rect {
        _visibleRect ?? screen.visibleRect.also { _visibleRect = $0 }
    }
}

// Note to myself: Don't use NSScreen.main, it's garbage
// 1. The name is misleading, it's supposed to be called "focusedScreen"
// 2. It's inaccurate because NSScreen.main doesn't work correctly from NSWorkspace.didActivateApplicationNotification &
//    kAXFocusedWindowChangedNotification callbacks.
extension NSScreen {
    fileprivate func toMonitor(monitorAppKitNsScreenScreensId: Int) -> Monitor {
        MonitorImpl(
            monitorAppKitNsScreenScreensId: monitorAppKitNsScreenScreensId,
            name: localizedName,
            rect: rect,
            visibleRect: visibleRect,
            isMain: isMainScreen,
        )
    }

    fileprivate var isMainScreen: Bool {
        frame.minX == 0 && frame.minY == 0
    }

    /// The property is a replacement for Apple's crazy ``frame``
    ///
    /// - For ``MacWindow.topLeftCorner``, (0, 0) is main screen top left corner, and positive y-axis goes down.
    /// - For ``frame``, (0, 0) is main screen bottom left corner, and positive y-axis goes up (which is crazy).
    ///
    /// The property "normalizes" ``frame``
    fileprivate var rect: Rect { frame.monitorFrameNormalized() }

    /// Same as ``rect`` but for ``visibleFrame``
    fileprivate var visibleRect: Rect { visibleFrame.monitorFrameNormalized() }
}

private let testMonitorRect = Rect(topLeftX: 0, topLeftY: 0, width: 1920, height: 1080)
private let testMonitor = MonitorImpl(
    monitorAppKitNsScreenScreensId: 1,
    name: "Test Monitor",
    rect: testMonitorRect,
    visibleRect: testMonitorRect,
    isMain: true,
)

/// Always returns the underlying physical screens, ignoring
/// ``Config/treatMultipleMonitorsAsOne``. Use ``monitors`` for the
/// "logical" view that respects the config.
@MainActor
var physicalMonitors: [Monitor] {
    isUnitTest
        ? [testMonitor]
        : NSScreen.screens.enumerated().map { $0.element.toMonitor(monitorAppKitNsScreenScreensId: $0.offset + 1) }
}

@MainActor
var mainMonitor: Monitor {
    physicalMainMonitor
}

/// Always returns the underlying physical main monitor regardless of
/// ``Config/treatMultipleMonitorsAsOne``. Used for coordinate
/// normalization (see ``CGRect/monitorFrameNormalized``).
nonisolated var physicalMainMonitor: Monitor {
    if isUnitTest { return testMonitor }
    let screens = NSScreen.screens
    // Fallback: If main screen can't be found (e.g., during display reconfiguration),
    // return screens.first or testMonitor to avoid crash
    let screen = screens.withIndex.singleOrNil(where: \.value.isMainScreen) ?? screens.first.map { (0, $0) }
    guard let screen else { return testMonitor }
    return LazyMonitor(monitorAppKitNsScreenScreensId: screen.index + 1, isMain: true, screen.value)
}

@MainActor
var monitors: [Monitor] {
    let physical = physicalMonitors
    if config.treatMultipleMonitorsAsOne, let combined = combineMonitors(physical) {
        return [combined]
    }
    return physical
}

@MainActor
var sortedMonitors: [Monitor] {
    monitors.sortedBy([\.rect.minX, \.rect.minY])
}
