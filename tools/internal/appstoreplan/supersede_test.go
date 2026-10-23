package appstoreplan

import (
	"strings"
	"testing"
)

func TestDecideKeepsTheSubmissionOnTheLatestRelease(t *testing.T) {
	queued := func(version string) *Version { return &Version{Version: version, State: "WAITING_FOR_REVIEW"} }
	cases := []struct {
		name       string
		report     Report
		releases   []Release
		action     Action
		version    string
		build      string
		supersedes string
		pending    string
		summary    string
	}{
		{
			name: "a processed newer release supersedes a queued version",
			report: Report{
				Live: live("5.1.0"), InFlight: queued("5.1.1"), Submission: &Submission{ID: "s1", State: "WAITING_FOR_REVIEW"},
				Builds: map[string]string{"5.1.1": "400", "5.2.0": "410", "5.2.1": "415"},
			},
			releases: releases("v5.2.1", "v5.2.0", "v5.1.1", "v5.1.0"),
			action:   Submit, version: "5.2.1", build: "415", supersedes: "5.1.1",
			summary: "submit 5.2.1 415 superseding 5.1.1",
		},
		{
			name:     "a queued version stays while the newer build is processing",
			report:   Report{Live: live("5.1.0"), InFlight: queued("5.1.1"), Submission: &Submission{ID: "s2", State: "WAITING_FOR_REVIEW"}, Builds: map[string]string{"5.1.1": "400"}},
			releases: releases("v5.2.1", "v5.1.1"),
			action:   WaitingForBuild, version: "5.2.1", pending: "5.2.1",
			summary: "waiting-for-build 5.2.1",
		},
		{
			name: "a version in review waits and notes the pending release",
			report: Report{
				Live: live("5.1.0"), InFlight: &Version{Version: "5.1.1", State: "IN_REVIEW"},
				Submission: &Submission{ID: "s3", State: "IN_REVIEW"}, Builds: map[string]string{"5.1.1": "400", "5.2.1": "415"},
			},
			releases: releases("v5.2.1", "v5.1.1"),
			action:   Wait, version: "5.2.1", pending: "5.2.1",
			summary: "wait",
		},
		{
			name:     "a queued version whose submission already started review is not withdrawn",
			report:   Report{Live: live("5.1.0"), InFlight: queued("5.1.1"), Submission: &Submission{ID: "s4", State: "IN_REVIEW"}, Builds: map[string]string{"5.2.1": "415"}},
			releases: releases("v5.2.1", "v5.1.1"),
			action:   Wait, version: "5.2.1", pending: "5.2.1",
			summary: "wait",
		},
		{
			name:     "an approved version pending release notes the newer release",
			report:   Report{Live: live("5.1.0"), InFlight: &Version{Version: "5.1.1", State: "PENDING_APPLE_RELEASE"}, Builds: map[string]string{"5.2.1": "415"}},
			releases: releases("v5.2.1", "v5.1.1"),
			action:   Wait, version: "5.2.1", pending: "5.2.1",
			summary: "wait",
		},
		{
			name:     "the live version is the latest release",
			report:   Report{Live: live("5.2.1"), Builds: map[string]string{"5.2.1": "415"}},
			releases: releases("v5.2.1", "v5.1.1"),
			action:   UpToDate, version: "5.2.1",
			summary: "up-to-date",
		},
		{
			name:     "a queued version that is the latest release keeps waiting",
			report:   Report{Live: live("5.1.0"), InFlight: queued("5.2.1"), Builds: map[string]string{"5.2.1": "415"}},
			releases: releases("v5.2.1", "v5.1.1"),
			action:   Wait, version: "5.2.1",
			summary: "wait",
		},
	}
	for _, test := range cases {
		t.Run(test.name, func(t *testing.T) {
			plan := Decide(test.report, test.releases)
			if plan.Action != test.action || plan.Version != test.version || plan.Build != test.build || plan.Supersedes != test.supersedes || plan.Pending != test.pending {
				t.Fatalf("got %+v", plan)
			}
			if plan.Summary() != test.summary {
				t.Fatalf("unexpected summary %q", plan.Summary())
			}
			if test.supersedes != "" && !strings.Contains(plan.Reason, "supersedes "+test.supersedes+" (WAITING_FOR_REVIEW)") {
				t.Fatalf("the reason does not name the superseded version: %q", plan.Reason)
			}
			if test.pending != "" && !strings.Contains(plan.Reason, test.pending) {
				t.Fatalf("the reason does not mention the pending release: %q", plan.Reason)
			}
			output := plan.Outputs()
			for _, line := range []string{"supersedes=" + test.supersedes + "\n", "pending=" + test.pending + "\n"} {
				if !strings.Contains(output, line) {
					t.Fatalf("missing %q in\n%s", line, output)
				}
			}
		})
	}
}
