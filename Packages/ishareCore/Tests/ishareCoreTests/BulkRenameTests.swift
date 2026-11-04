import Foundation
import Testing
@testable import ishareCore

struct BulkRenameTests {
    let date = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func numbersAndFillsPlaceholders() {
        let names = (1 ... 12).map { "shot\($0).png" }
        let titles = BulkRename.titles(template: "Onboarding {{n}}", originals: names, date: date)
        #expect(titles.first == "Onboarding 01")
        #expect(titles.last == "Onboarding 12")
        #expect(BulkRename.titles(template: "{{name}} {{date}}", originals: ["a.png"], date: date) == ["a 2027-01-15"])
    }

    @Test func addsNumbersWhenTheTemplateHasNone() {
        #expect(BulkRename.titles(template: "Bug", originals: ["a", "b"], date: date) == ["Bug 1", "Bug 2"])
        #expect(BulkRename.titles(template: " ", originals: ["a"], date: date) == ["a"])
    }

    @Test func computesExpiryDates() {
        #expect(BulkRename.expiry(days: 7, from: date) == date.addingTimeInterval(7 * 86400))
        #expect(BulkRename.expiry(days: nil, from: date) == nil)
    }
}
