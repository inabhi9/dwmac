@testable import AppBundle
import XCTest

@MainActor
final class WorkspaceLayoutTest: XCTestCase {
    override func setUp() async throws {
        setUpWorkspacesForTests()
    }

    func testLayoutMasterStackWithInnerGaps() async throws {
        // Setup config with inner gaps
        config.gaps = Gaps(
            inner: .init(vertical: 10, horizontal: 10),
            outer: .zero,
        )

        let workspace = Workspace.get(byName: "test")
        workspace.layout = .masterStack
        workspace.orientation = .h

        // Add 2 windows with initial rects
        let initialRect = Rect(topLeftX: 0, topLeftY: 0, width: 100, height: 100)
        let w1 = TestWindow.new(id: 1, parent: workspace, rect: initialRect)
        let w2 = TestWindow.new(id: 2, parent: workspace, rect: initialRect)

        // Layout
        try await workspace.layoutWorkspace()

        // Monitor is 1920x1080. Outer gaps 0.
        // Available width = 1920. Available height = 1080 (passed as 1079 in layoutWorkspace)
        // Master width = (1920 - 10) * 0.5 = 955.
        // Master height = 1079.

        // Note: Floating point comparisons might require accuracy, but using Integers here
        XCTAssertEqual(w1.lastAppliedLayoutPhysicalRect?.width, 955)
        XCTAssertEqual(w1.lastAppliedLayoutPhysicalRect?.height, 1079)
        XCTAssertEqual(w1.lastAppliedLayoutPhysicalRect?.topLeftX, 0)
        XCTAssertEqual(w1.lastAppliedLayoutPhysicalRect?.topLeftY, 0)

        // Stack X = 955 + 10 = 965.
        XCTAssertEqual(w2.lastAppliedLayoutPhysicalRect?.topLeftX, 965)
        XCTAssertEqual(w2.lastAppliedLayoutPhysicalRect?.width, 955)
        XCTAssertEqual(w2.lastAppliedLayoutPhysicalRect?.height, 1079)
    }

    func testLayoutMasterStackWithInnerGaps_Vertical() async throws {
        config.gaps = Gaps(
            inner: .init(vertical: 10, horizontal: 10),
            outer: .zero,
        )
        let workspace = Workspace.get(byName: "testV")
        workspace.layout = .masterStack
        workspace.orientation = .v

        let initialRect = Rect(topLeftX: 0, topLeftY: 0, width: 100, height: 100)
        let w1 = TestWindow.new(id: 1, parent: workspace, rect: initialRect)
        let w2 = TestWindow.new(id: 2, parent: workspace, rect: initialRect)

        try await workspace.layoutWorkspace()

        // Master Height = (1079 - 10) * 0.5 = 1069 * 0.5 = 534.5
        // Master Width = 1920

        XCTAssertEqual(w1.lastAppliedLayoutPhysicalRect?.width, 1920)
        XCTAssertEqual(w1.lastAppliedLayoutPhysicalRect?.height, 534.5)

        // Stack Y = 534.5 + 10 = 544.5
        // Stack Height = 534.5
        XCTAssertEqual(w2.lastAppliedLayoutPhysicalRect?.topLeftY, 544.5)
        XCTAssertEqual(w2.lastAppliedLayoutPhysicalRect?.height, 534.5)
    }

    func testLayoutMasterStackRightMaster() async throws {
        config.gaps = Gaps(
            inner: .init(vertical: 10, horizontal: 10),
            outer: .zero,
        )
        config.masterPosition = .right
        defer { config.masterPosition = .left } // Reset after test

        let workspace = Workspace.get(byName: "testRightMaster")
        workspace.layout = .masterStack
        workspace.orientation = .h

        let initialRect = Rect(topLeftX: 0, topLeftY: 0, width: 100, height: 100)
        let w1 = TestWindow.new(id: 1, parent: workspace, rect: initialRect)
        let w2 = TestWindow.new(id: 2, parent: workspace, rect: initialRect)

        try await workspace.layoutWorkspace()

        // Available width = 1920. Gaps = 10.
        // Master Width = 955. Stack Width = 955.

        // Master (w1) should be on the RIGHT.
        // X = 0 + StackWidth (955) + Gap (10) = 965.
        XCTAssertEqual(w1.lastAppliedLayoutPhysicalRect?.topLeftX, 965)
        XCTAssertEqual(w1.lastAppliedLayoutPhysicalRect?.width, 955)

        // Stack (w2) should be on the LEFT.
        // X = 0.
        XCTAssertEqual(w2.lastAppliedLayoutPhysicalRect?.topLeftX, 0)
        XCTAssertEqual(w2.lastAppliedLayoutPhysicalRect?.width, 955)
    }

    func testLayoutMonocleWhenStackLimitIsZero() async throws {
        config.gaps = .zero
        config.stackWindowsLimit = 0
        defer { config.stackWindowsLimit = -1 } // Reset after test

        let workspace = Workspace.get(byName: "testMonocle")
        workspace.layout = .masterStack
        workspace.orientation = .h

        let initialRect = Rect(topLeftX: 0, topLeftY: 0, width: 100, height: 100)
        let w1 = TestWindow.new(id: 1, parent: workspace, rect: initialRect)
        let w2 = TestWindow.new(id: 2, parent: workspace, rect: initialRect)
        let w3 = TestWindow.new(id: 3, parent: workspace, rect: initialRect)

        try await workspace.layoutWorkspace()

        // Only the master (w1) is tiled, filling the whole monitor (1920x1079).
        XCTAssertEqual(w1.lastAppliedLayoutPhysicalRect?.topLeftX, 0)
        XCTAssertEqual(w1.lastAppliedLayoutPhysicalRect?.topLeftY, 0)
        XCTAssertEqual(w1.lastAppliedLayoutPhysicalRect?.width, 1920)
        XCTAssertEqual(w1.lastAppliedLayoutPhysicalRect?.height, 1079)

        // Every other window is removed from the layout and hidden off-screen.
        XCTAssertNotNil(w2.hiddenInCorner)
        XCTAssertNotNil(w3.hiddenInCorner)
    }

    func testLayoutLimitedStackHidesOverflowOffScreen() async throws {
        config.gaps = .zero
        config.stackWindowsLimit = 1
        defer { config.stackWindowsLimit = -1 } // Reset after test

        let workspace = Workspace.get(byName: "testLimitedStack")
        workspace.layout = .masterStack
        workspace.orientation = .h

        let initialRect = Rect(topLeftX: 0, topLeftY: 0, width: 100, height: 100)
        // Insertion order matches production: first bound window ends up at the top (master).
        let master = TestWindow.new(id: 1, parent: workspace, rect: initialRect)
        let visibleStack = TestWindow.new(id: 2, parent: workspace, rect: initialRect)
        let overflow = TestWindow.new(id: 3, parent: workspace, rect: initialRect)

        try await workspace.layoutWorkspace()

        // Master takes the left half.
        XCTAssertEqual(master.lastAppliedLayoutPhysicalRect?.topLeftX, 0)
        XCTAssertEqual(master.lastAppliedLayoutPhysicalRect?.width, 960)
        XCTAssertEqual(master.lastAppliedLayoutPhysicalRect?.height, 1079)

        // The single allowed stack window takes the right half at full height.
        XCTAssertEqual(visibleStack.lastAppliedLayoutPhysicalRect?.topLeftX, 960)
        XCTAssertEqual(visibleStack.lastAppliedLayoutPhysicalRect?.width, 960)
        XCTAssertEqual(visibleStack.lastAppliedLayoutPhysicalRect?.height, 1079)

        // The overflow window is removed from the stack and hidden off-screen,
        // never covering a tiled window.
        XCTAssertNotNil(overflow.hiddenInCorner)
    }

    func testLayoutLimitedStackAttachBelowPushesTopmostOut() async throws {
        config.gaps = .zero
        config.stackWindowsLimit = 2
        config.attachBelow = true
        defer {
            config.stackWindowsLimit = -1
            config.attachBelow = false
        }

        let workspace = Workspace.get(byName: "testAttachBelowLimit")
        workspace.layout = .masterStack
        workspace.orientation = .h

        let initialRect = Rect(topLeftX: 0, topLeftY: 0, width: 100, height: 100)
        // With attach-below the first window is the master and the rest are appended in order.
        let master = TestWindow.new(id: 1, parent: workspace, rect: initialRect)
        let oldest = TestWindow.new(id: 2, parent: workspace, rect: initialRect)
        let middle = TestWindow.new(id: 3, parent: workspace, rect: initialRect)
        let newest = TestWindow.new(id: 4, parent: workspace, rect: initialRect)

        try await workspace.layoutWorkspace()

        // Master fills the left half.
        XCTAssertEqual(master.lastAppliedLayoutPhysicalRect?.topLeftX, 0)
        XCTAssertEqual(master.lastAppliedLayoutPhysicalRect?.width, 960)

        // The two newest windows are the visible stack (top-to-bottom: middle, newest).
        XCTAssertEqual(middle.lastAppliedLayoutPhysicalRect?.topLeftX, 960)
        XCTAssertEqual(middle.lastAppliedLayoutPhysicalRect?.topLeftY, 0)
        XCTAssertEqual(middle.lastAppliedLayoutPhysicalRect?.height, 539.5)

        XCTAssertEqual(newest.lastAppliedLayoutPhysicalRect?.topLeftX, 960)
        XCTAssertEqual(newest.lastAppliedLayoutPhysicalRect?.topLeftY, 539.5)
        XCTAssertEqual(newest.lastAppliedLayoutPhysicalRect?.height, 539.5)

        // The oldest stacked window is pushed out of the stack and hidden off-screen.
        XCTAssertNotNil(oldest.hiddenInCorner)
    }

    func testFocusingHiddenWindowPullsItIntoView() async throws {
        setUpWorkspacesForTests()
        config.gaps = .zero
        config.stackWindowsLimit = 1
        defer { config.stackWindowsLimit = -1 } // Reset after test

        let workspace = Workspace.get(byName: name)
        workspace.layout = .masterStack
        workspace.orientation = .h

        let initialRect = Rect(topLeftX: 0, topLeftY: 0, width: 100, height: 100)
        let master = TestWindow.new(id: 1, parent: workspace, rect: initialRect)
        let stack = TestWindow.new(id: 2, parent: workspace, rect: initialRect)
        let hidden = TestWindow.new(id: 3, parent: workspace, rect: initialRect)

        // With a limit of 1, window 3 starts out hidden off-screen.
        _ = master.focusWindow()
        try await workspace.layoutWorkspace()
        XCTAssertNotNil(hidden.hiddenInCorner)
        XCTAssertNil(stack.hiddenInCorner)

        // Focusing the hidden window pulls it into the visible stack; the previously
        // visible stack window takes its place off-screen, and the master is untouched.
        _ = hidden.focusWindow()
        try await workspace.layoutWorkspace()

        XCTAssertNil(hidden.hiddenInCorner)
        XCTAssertEqual(hidden.lastAppliedLayoutPhysicalRect?.topLeftX, 960)
        XCTAssertEqual(hidden.lastAppliedLayoutPhysicalRect?.width, 960)

        XCTAssertNotNil(stack.hiddenInCorner)

        XCTAssertNil(master.hiddenInCorner)
        XCTAssertEqual(master.lastAppliedLayoutPhysicalRect?.topLeftX, 0)
        XCTAssertEqual(master.lastAppliedLayoutPhysicalRect?.width, 960)
        XCTAssertEqual(focus.windowOrNil?.windowId, 3)
    }

    func testHiddenWindowStaysHiddenWhenVisibleWindowRemoved() async throws {
        config.gaps = .zero
        config.stackWindowsLimit = 1
        defer { config.stackWindowsLimit = -1 } // Reset after test

        let workspace = Workspace.get(byName: "testStickyHidden")
        workspace.layout = .masterStack
        workspace.orientation = .h

        let rect = Rect(topLeftX: 0, topLeftY: 0, width: 100, height: 100)
        let master = TestWindow.new(id: 1, parent: workspace, rect: rect)
        let visible = TestWindow.new(id: 2, parent: workspace, rect: rect)
        let hidden = TestWindow.new(id: 3, parent: workspace, rect: rect)

        // With a limit of 1, window 3 is hidden off-screen.
        try await workspace.layoutWorkspace()
        XCTAssertTrue(hidden.isStackHidden)
        XCTAssertNotNil(hidden.hiddenInCorner)
        XCTAssertFalse(visible.isStackHidden)

        // Remove the visible stack window (like closing / minimizing / native-hiding it).
        visible.closeAxWindow()
        try await workspace.layoutWorkspace()

        // The hidden window must NOT be resurfaced; only the master remains tiled (full-screen).
        XCTAssertTrue(hidden.isStackHidden)
        XCTAssertNotNil(hidden.hiddenInCorner)
        XCTAssertEqual(master.lastAppliedLayoutPhysicalRect?.width, 1920)
    }

    func testRemovalFocusPrefersVisibleWindowOverHidden() async throws {
        setUpWorkspacesForTests()
        config.stackWindowsLimit = 1
        defer { config.stackWindowsLimit = -1 } // Reset after test

        let workspace = Workspace.get(byName: name)
        workspace.layout = .masterStack
        _ = TestWindow.new(id: 1, parent: workspace) // master
        _ = TestWindow.new(id: 2, parent: workspace) // visible stack
        let hidden = TestWindow.new(id: 3, parent: workspace) // hidden by the limit

        workspace.enforceStackWindowsLimit()
        XCTAssertTrue(hidden.isStackHidden)

        // The workspace's focus target skips the hidden window even though it is the most
        // recently added (so closing the focused window won't jump focus onto a hidden one).
        XCTAssertNotEqual(workspace.toLiveFocus().windowOrNil?.windowId, 3)
    }

    func testFocusedWindowStaysVisibleAcrossRelayouts() async throws {
        setUpWorkspacesForTests()
        config.gaps = .zero
        config.stackWindowsLimit = 1
        defer { config.stackWindowsLimit = -1 } // Reset after test

        let workspace = Workspace.get(byName: name)
        workspace.layout = .masterStack
        workspace.orientation = .h

        let rect = Rect(topLeftX: 0, topLeftY: 0, width: 100, height: 100)
        let master = TestWindow.new(id: 1, parent: workspace, rect: rect)
        _ = TestWindow.new(id: 2, parent: workspace, rect: rect)
        let hidden = TestWindow.new(id: 3, parent: workspace, rect: rect)

        _ = master.focusWindow()
        try await workspace.layoutWorkspace()
        XCTAssertTrue(hidden.isStackHidden)

        // Explicitly focus the hidden window, then relayout several times. A focused tiling
        // window must remain visible (never re-hidden by the stack-limit enforcement).
        _ = hidden.focusWindow()
        for _ in 0 ..< 3 {
            try await workspace.layoutWorkspace()
            XCTAssertFalse(hidden.isStackHidden, "focused window must stay visible")
            XCTAssertNil(hidden.hiddenInCorner)
            XCTAssertEqual(focus.windowOrNil?.windowId, 3)
        }
    }

    func testRemovingMasterPromotesVisibleNotHiddenWindow() async throws {
        config.gaps = .zero
        config.stackWindowsLimit = 1
        config.attachBelow = true // stack windows right after the master are the hidden (oldest) ones
        defer {
            config.stackWindowsLimit = -1
            config.attachBelow = false
        }

        let workspace = Workspace.get(byName: "testMasterPromotion")
        workspace.layout = .masterStack
        workspace.orientation = .h

        let rect = Rect(topLeftX: 0, topLeftY: 0, width: 100, height: 100)
        let master = TestWindow.new(id: 1, parent: workspace, rect: rect)
        let oldest = TestWindow.new(id: 2, parent: workspace, rect: rect) // hidden by the limit
        let newest = TestWindow.new(id: 3, parent: workspace, rect: rect) // visible stack

        try await workspace.layoutWorkspace()
        // With attach-below + limit 1: id 2 (right after master) is hidden, id 3 is visible.
        XCTAssertTrue(oldest.isStackHidden)
        XCTAssertFalse(newest.isStackHidden)

        // Remove the master. Naively id 2 would shift into the master slot, but it is hidden;
        // the visible window (id 3) must be promoted instead, and id 2 stays hidden.
        master.closeAxWindow()
        try await workspace.layoutWorkspace()

        XCTAssertEqual(workspace.tilingWindows.first?.windowId, 3)
        XCTAssertFalse(newest.isStackHidden)
        XCTAssertTrue(oldest.isStackHidden)
        XCTAssertNotNil(oldest.hiddenInCorner)
        XCTAssertEqual(newest.lastAppliedLayoutPhysicalRect?.width, 1920) // promoted master fills screen
    }
}
