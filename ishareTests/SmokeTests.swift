import Testing
@testable import ishare

struct SmokeTests {
    @Test func bundleIdentifierMatches() {
        #expect(Bundle.main.bundleIdentifier == "dev.adrian.ishare")
    }
}
