import Foundation
import Testing
@testable import ishare

struct ReviewPromptPolicyTests {
    let policy = ReviewPromptPolicy()
    let install = Date(timeIntervalSince1970: 1_800_000_000)
    let day = ReviewPromptPolicy.day

    func state(successes: Int, installedDaysAgo: Double = 10, now: Date) -> ReviewPromptState {
        ReviewPromptState(installDate: now.addingTimeInterval(-installedDaysAgo * day), successesSincePrompt: successes)
    }

    func recordSuccesses(_ count: Int, from state: ReviewPromptState, at now: Date) -> ReviewPromptState {
        (0 ..< count).reduce(state) { current, _ in policy.recording(succeeded: true, in: current, now: now) }
    }

    @Test func becomesEligibleAfterTenSuccessesOnceTheInstallSettled() {
        let now = install.addingTimeInterval(4 * day)
        var current = ReviewPromptState(installDate: install)
        current = recordSuccesses(9, from: current, at: now)
        #expect(!policy.isEligible(current, now: now))
        current = recordSuccesses(1, from: current, at: now)
        #expect(policy.isEligible(current, now: now))
    }

    @Test func waitsThreeDaysAfterInstall() {
        let fresh = recordSuccesses(20, from: ReviewPromptState(), at: install)
        #expect(fresh.installDate == install)
        #expect(!policy.isEligible(fresh, now: install.addingTimeInterval(2.9 * day)))
        #expect(policy.isEligible(fresh, now: install.addingTimeInterval(3 * day)))
    }

    @Test func usesTheOldestHistoryDateAsTheInstallDate() {
        let now = install.addingTimeInterval(30 * day)
        let recorded = policy.recording(succeeded: true, in: ReviewPromptState(), now: now, installedAt: install)
        #expect(recorded.installDate == install)
        let future = policy.recording(succeeded: true, in: ReviewPromptState(), now: now, installedAt: now.addingTimeInterval(day))
        #expect(future.installDate == now)
    }

    @Test func holdsOffForThreeDaysAfterAFailedUpload() {
        let now = install.addingTimeInterval(20 * day)
        var current = state(successes: 15, now: now)
        current = policy.recording(succeeded: false, in: current, now: now)
        #expect(current.lastFailure == now)
        #expect(current.successesSincePrompt == 15)
        #expect(!policy.isEligible(current, now: now.addingTimeInterval(2 * day)))
        #expect(policy.isEligible(current, now: now.addingTimeInterval(3 * day)))
    }

    @Test func doesNotAskAgainForNinetyDays() {
        let now = install.addingTimeInterval(20 * day)
        let prompted = policy.prompted(state(successes: 10, now: now), now: now)
        #expect(prompted.successesSincePrompt == 0)
        #expect(prompted.lastPrompt == now)
        let later = now.addingTimeInterval(89 * day)
        #expect(!policy.isEligible(recordSuccesses(50, from: prompted, at: later), now: later))
        let muchLater = now.addingTimeInterval(90 * day)
        #expect(!policy.isEligible(recordSuccesses(9, from: prompted, at: muchLater), now: muchLater))
        #expect(policy.isEligible(recordSuccesses(10, from: prompted, at: muchLater), now: muchLater))
    }

    @Test func respectsACustomThreshold() {
        let custom = ReviewPromptPolicy(requiredSuccesses: 3)
        let now = install.addingTimeInterval(10 * day)
        #expect(custom.isEligible(state(successes: 3, now: now), now: now))
        #expect(!custom.isEligible(state(successes: 2, now: now), now: now))
    }

    @Test func stateRoundTripsThroughJSON() throws {
        let original = ReviewPromptState(installDate: install, successesSincePrompt: 4, lastFailure: install, lastPrompt: nil)
        let data = try JSONEncoder().encode(original)
        #expect(try JSONDecoder().decode(ReviewPromptState.self, from: data) == original)
    }
}

struct ReviewPromptMomentTests {
    @Test func isCalmOnlyWhenNothingIsGoingOn() {
        #expect(ReviewPromptMoment().isCalm)
        #expect(!ReviewPromptMoment(isRecording: true).isCalm)
        #expect(!ReviewPromptMoment(isUploading: true).isCalm)
        #expect(!ReviewPromptMoment(hasModalWindow: true).isCalm)
        #expect(!ReviewPromptMoment(hasSheet: true).isCalm)
        #expect(!ReviewPromptMoment(hasFloatingPanel: true).isCalm)
    }
}

@MainActor
struct ReviewPromptAvailabilityTests {
    @Test func neverPromptsInTheGitHubBuildOrDuringTests() {
        #expect(!ReviewPrompt.isSupported)
    }
}
