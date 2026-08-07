public struct MinimizeAllWindowsButCurrentCmdArgs: CmdArgs {
    /*conforms*/ public var commonState: CmdArgsCommonState
    public init(rawArgs: StrArrSlice) { self.commonState = .init(rawArgs) }
    public static let parser: CmdParser<Self> = cmdParser(
        kind: .minimizeAllWindowsButCurrent,
        allowInConfig: true,
        help: minimize_all_windows_but_current_help_generated,
        flags: [:],
        posArgs: [],
    )
}

public func parseMinimizeAllWindowsButCurrentCmdArgs(_ args: StrArrSlice) -> ParsedCmd<MinimizeAllWindowsButCurrentCmdArgs> {
    parseSpecificCmdArgs(MinimizeAllWindowsButCurrentCmdArgs(rawArgs: args), args)
}
