@testable import AppBundle
import XCTest

@MainActor
final class StackWindowsLimitTest: XCTestCase {
    func testParseStackWindowsLimit() {
        let (config, errors) = parseConfig(
            """
            stack-windows-limit = 2
            """
        )
        assertEquals(errors, [])
        assertEquals(config.stackWindowsLimit, 2)
    }

    func testParseStackWindowsLimitZero() {
        let (config, errors) = parseConfig(
            """
            stack-windows-limit = 0
            """
        )
        assertEquals(errors, [])
        assertEquals(config.stackWindowsLimit, 0)
    }

    func testParseStackWindowsLimitDefault() {
        let (config, errors) = parseConfig("")
        assertEquals(errors, [])
        assertEquals(config.stackWindowsLimit, -1)
    }

    func testParseStackWindowsLimitInvalid() {
        let (_, errors) = parseConfig(
            """
            stack-windows-limit = -2
            """
        )
        assertEquals(errors.descriptions, ["stack-windows-limit: Must be >= -1"])
    }
}
