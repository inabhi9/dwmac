@testable import AppBundle
import XCTest

@MainActor
final class TreatMultipleMonitorsAsOneTest: XCTestCase {
    func testParseTreatMultipleMonitorsAsOneTrue() {
        let (config, errors) = parseConfig(
            """
            treat-multiple-monitors-as-one = true
            """
        )
        assertEquals(errors, [])
        assertEquals(config.treatMultipleMonitorsAsOne, true)
    }

    func testParseTreatMultipleMonitorsAsOneFalse() {
        let (config, errors) = parseConfig(
            """
            treat-multiple-monitors-as-one = false
            """
        )
        assertEquals(errors, [])
        assertEquals(config.treatMultipleMonitorsAsOne, false)
    }

    func testParseTreatMultipleMonitorsAsOneDefault() {
        let (config, errors) = parseConfig("")
        assertEquals(errors, [])
        assertEquals(config.treatMultipleMonitorsAsOne, false)
    }

    func testParseTreatMultipleMonitorsAsOneInvalid() {
        let (_, errors) = parseConfig(
            """
            treat-multiple-monitors-as-one = 'yes'
            """
        )
        assertEquals(
            errors.descriptions,
            ["treat-multiple-monitors-as-one: Expected type is 'bool'. But actual type is 'string'"],
        )
    }
}
