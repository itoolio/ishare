import Testing
@testable import ishareCore

struct FeatureTourPolicyTests {
    func shows(seen: String? = nil, last: [Int]?, onboarded: Bool = true, suppressed: Bool = false) -> Bool {
        FeatureTourPolicy.shouldPresent(
            tourID: "5.7", introducedIn: [5, 7], seenTourID: seen, lastLaunched: last, hasCompletedOnboarding: onboarded, isSuppressed: suppressed)
    }

    @Test func showsOnceToPeopleUpdatingFromAnOlderVersion() {
        #expect(shows(last: [5, 3, 2]))
        #expect(shows(last: [5, 6, 0]))
        #expect(!shows(seen: "5.7", last: [5, 6, 0]))
    }

    @Test func skipsNewInstallsAndCurrentVersions() {
        #expect(!shows(last: nil))
        #expect(!shows(last: [5, 7, 0]))
        #expect(!shows(last: [5, 8]))
        #expect(!shows(last: [5, 6], onboarded: false))
        #expect(!shows(last: [5, 6], suppressed: true))
    }
}
