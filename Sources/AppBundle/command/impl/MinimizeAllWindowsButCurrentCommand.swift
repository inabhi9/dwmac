import AppKit
import Common

struct MinimizeAllWindowsButCurrentCommand: Command {
    let args: MinimizeAllWindowsButCurrentCmdArgs
    /*conforms*/ var shouldResetClosedWindowsCache = false

    func run(_ env: CmdEnv, _ io: CmdIo) async throws -> Bool {
        guard let target = args.resolveTargetOrReportError(env, io) else { return false }
        guard let focused = target.windowOrNil else {
            return io.err("Empty workspace")
        }
        guard let workspace = focused.nodeWorkspace else {
            return io.err("Focused window '\(focused.windowId)' doesn't belong to workspace")
        }

        // Master (first tiling window) is left as is. The rest of the stack and all
        // floating windows are minimized, except the currently focused window.
        let stack = workspace.tilingWindows.dropFirst()
        let toMinimize = (stack + workspace.floatingWindows).filter { $0 != focused }

        var result = true
        for window in toMinimize {
            // Native minimize state can drift ahead of the tree (normalizeLayoutReason hasn't
            // rebound the window into macosMinimizedWindowsContainer yet). Skip it instead of
            // letting MacosNativeMinimizeCommand toggle it back to unminimized.
            if try await window.isMacosMinimized { continue }
            result = try await MacosNativeMinimizeCommand(args: MacosNativeMinimizeCmdArgs(rawArgs: []))
                .run(env.copy(\.windowId, window.windowId), io) && result
        }
        return result
    }
}
