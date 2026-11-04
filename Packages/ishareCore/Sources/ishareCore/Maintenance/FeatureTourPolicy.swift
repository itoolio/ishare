import Foundation

public enum FeatureTourPolicy {
    public static func shouldPresent(
        tourID: String, introducedIn version: [Int], seenTourID: String?, lastLaunched: [Int]?, hasCompletedOnboarding: Bool, isSuppressed: Bool
    ) -> Bool {
        guard !isSuppressed, hasCompletedOnboarding, seenTourID != tourID, let lastLaunched else { return false }
        return lastLaunched.lexicographicallyPrecedes(version)
    }
}
