package releaseretry

import (
	"strings"
	"testing"
)

func decide(t *testing.T, payload string, attempt int) Decision {
	t.Helper()
	jobs, err := Parse(strings.NewReader(payload))
	if err != nil {
		t.Fatal(err)
	}
	return Decide(jobs, attempt)
}

func TestRetriesJobsThatWereCancelledWithoutAFailingStep(t *testing.T) {
	decision := decide(t, `{"jobs":[{"name":"build","conclusion":"success","steps":[]},{"name":"checks / app-store-tests","conclusion":"cancelled","steps":[{"name":"Run tests","conclusion":"cancelled"}]}]}`, 1)
	if !decision.Retry {
		t.Fatalf("expected a retry: %s", decision.Reason)
	}
}

func TestRetriesJobsThatLostTheirRunnerWithoutSteps(t *testing.T) {
	if !decide(t, `{"jobs":[{"name":"app","conclusion":"failure","steps":[]}]}`, 2).Retry {
		t.Fatal("expected a retry for a job without steps")
	}
}

func TestDoesNotRetryRealFailures(t *testing.T) {
	decision := decide(t, `{"jobs":[{"name":"app","conclusion":"failure","steps":[{"name":"Run unit tests","conclusion":"failure"}]},{"name":"ui","conclusion":"cancelled","steps":[]}]}`, 1)
	if decision.Retry || !strings.Contains(decision.Reason, "Run unit tests") {
		t.Fatalf("unexpected decision %+v", decision)
	}
}

func TestStopsAfterTheAttemptLimit(t *testing.T) {
	if decide(t, `{"jobs":[{"name":"app","conclusion":"cancelled","steps":[]}]}`, MaxAttempts).Retry {
		t.Fatal("expected no retry at the attempt limit")
	}
}

func TestDoesNothingWhenNothingFailed(t *testing.T) {
	if decide(t, `{"jobs":[{"name":"app","conclusion":"success","steps":[]}]}`, 1).Retry {
		t.Fatal("expected no retry")
	}
}
