@testable import AppBundle
import AppKit

final class TestWindow: Window, CustomStringConvertible {
    private var _rect: Rect?

    @MainActor
    private init(_ id: UInt32, _ parent: NonLeafDwNodeObject, _ rect: Rect?) {
        _rect = rect
        super.init(id: id, TestApp.shared, lastFloatingSize: nil, parent: parent, index: INDEX_BIND_LAST)
    }

    @discardableResult
    @MainActor
    static func new(id: UInt32, parent: NonLeafDwNodeObject, rect: Rect? = nil) -> TestWindow {
        let wi = TestWindow(id, parent, rect)
        TestApp.shared._windows.append(wi)
        return wi
    }

    nonisolated var description: String { "TestWindow(\(windowId))" }

    // Records the corner a window was hidden into (nil == currently tiled/visible).
    private(set) var hiddenInCorner: OptimalHideCorner? = nil

    @MainActor
    override func hideInCorner(_ corner: OptimalHideCorner) async throws {
        hiddenInCorner = corner
    }

    @MainActor
    override func nativeFocus() {
        appForTests = TestApp.shared
        TestApp.shared.focusedWindow = self
    }

    override func closeAxWindow() {
        unbindFromParent()
    }

    override var title: String {
        get async { // redundant async. todo create bug report to Swift
            description
        }
    }

    @MainActor override func getAxRect() async throws -> Rect? { // todo change to not Optional
        _rect
    }

    override func setAxFrame(_ topLeft: CGPoint?, _ size: CGSize?) {
        hiddenInCorner = nil // positioning on-screen unhides the window
        guard let old = _rect else { return }
        let newTopLeft = topLeft ?? old.topLeftCorner
        let newSize = size ?? old.size
        _rect = Rect(topLeftX: newTopLeft.x, topLeftY: newTopLeft.y, width: newSize.width, height: newSize.height)
    }
}
