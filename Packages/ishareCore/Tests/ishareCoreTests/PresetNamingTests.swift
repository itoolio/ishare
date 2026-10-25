import Foundation
import Testing
@testable import ishareCore

struct PresetNamingTests {
    @Test func keepsAFreeName() {
        #expect(PresetNaming.uniqueName(" Demo ", among: ["Tutorial"], copySuffix: "copy") == "Demo")
    }

    @Test func numbersDuplicateCopies() {
        #expect(PresetNaming.uniqueName("Demo", among: ["Demo"], copySuffix: "copy") == "Demo copy")
        #expect(PresetNaming.uniqueName("Demo", among: ["demo", "Demo Copy"], copySuffix: "copy") == "Demo copy 2")
        #expect(PresetNaming.uniqueName("Demo", among: ["Demo", "Demo copy", "Demo copy 2"], copySuffix: "copy") == "Demo copy 3")
    }

    @Test func findsPresetsByIDOrName() {
        let items = [("a1", "Bug Report"), ("b2", "Démo 4K"), ("c3", "Demo Short")]
        func find(_ query: String) -> Int? {
            PresetNaming.index(matching: query, in: items, id: \.0, name: \.1)
        }
        #expect(find("bug report") == 0)
        #expect(find("demo 4k") == 1)
        #expect(find("B2") == 1)
        #expect(find("bug") == 0)
        #expect(find("demo") == nil)
        #expect(find("  ") == nil)
        #expect(find("missing") == nil)
    }

    @Test func movesAnItemWithinBounds() {
        #expect(PresetNaming.moved([1, 2, 3], from: 0, by: 1) == [2, 1, 3])
        #expect(PresetNaming.moved([1, 2, 3], from: 2, by: -2) == [3, 1, 2])
        #expect(PresetNaming.moved([1, 2, 3], from: 2, by: 1) == [1, 2, 3])
    }
}
