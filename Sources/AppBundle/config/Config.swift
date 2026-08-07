import AppKit
import Common
import HotKey
import OrderedCollections

func getDefaultConfigUrlFromProject() -> URL {
    var url = URL(filePath: #filePath)
    check(FileManager.default.fileExists(atPath: url.path))
    while !FileManager.default.fileExists(atPath: url.appending(component: ".git").path) {
        url.deleteLastPathComponent()
    }
    let projectRoot: URL = url
    return projectRoot.appending(component: "docs/config-examples/default-config.toml")
}

var defaultConfigUrl: URL {
    if isUnitTest {
        return getDefaultConfigUrlFromProject()
    } else {
        return Bundle.main.url(forResource: "default-config", withExtension: "toml")
            // Useful for debug builds that are not app bundles
            ?? getDefaultConfigUrlFromProject()
    }
}
@MainActor let defaultConfig: Config = {
    let parsedConfig = parseConfig(Result { try String(contentsOf: defaultConfigUrl, encoding: .utf8) }.getOrDie())
    if !parsedConfig.errors.isEmpty {
        die("Can't parse default config: \(parsedConfig.errors)")
    }
    return parsedConfig.config
}()
@MainActor var config: Config = defaultConfig // todo move to Ctx?
@MainActor var configUrl: URL = defaultConfigUrl

struct Config: ConvenienceCopyable {
    var configVersion: Int = 1
    var afterLoginCommand: [any Command] = []
    var afterStartupCommand: [any Command] = []
    var _indentForNestedContainersWithTheSameOrientation: Void = ()
    var _nonEmptyWorkspacesRootContainersLayoutOnStartup: Void = ()
    var defaultRootContainerLayout: Layout = .masterStack
    var defaultRootContainerOrientation: DefaultContainerOrientation = .auto
    var startAtLogin: Bool = false
    var automaticallyUnhideMacosHiddenApps: Bool = false
    var persistentWorkspaces: OrderedSet<String> = []
    var execOnWorkspaceChange: [String] = [] // todo deprecate
    var defaultMfact: Double = 0.5
    var attachBelow: Bool = false
    var centerFloatingWindows: Bool = false
    var keyMapping = KeyMapping()
    var mod: String = "" // User defined modifier alias
    var execConfig: ExecConfig = ExecConfig()

    var onFocusChanged: [any Command] = []
    var onFocusedMonitorChanged: [any Command] = []

    var gaps: Gaps = .zero
    var workspaceToMonitorForceAssignment: [String: [MonitorDescription]] = [:]
    var modes: [String: Mode] = [:]
    var onWindowDetected: [WindowDetectedCallback] = []
    var onModeChanged: [any Command] = []
    var masterPosition: MasterPosition = .left
    // Maximum number of stacked (non-master) windows to tile.
    // -1 means unlimited (all stacked windows are tiled).
    //  0 means no stack: only the master is tiled and every other window is hidden
    //    off-screen (monocle-like); a new window becomes the master.
    // >0 limits the visible stack; windows beyond the limit are removed from the stack and
    //    hidden off-screen. With `attach-below` a new window stays visible at the bottom of
    //    the stack and pushes the oldest (topmost) window out; otherwise the oldest window
    //    falls off the bottom.
    var stackWindowsLimit: Int = -1
}

enum DefaultContainerOrientation: String {
    case horizontal, vertical, auto
}

enum MasterPosition: String {
    case left, right
}
