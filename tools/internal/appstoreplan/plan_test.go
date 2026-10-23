package appstoreplan

import (
	"strings"
	"testing"
)

func releases(tags ...string) []Release {
	result := make([]Release, len(tags))
	for index, tag := range tags {
		result[index] = Release{TagName: tag}
	}
	return result
}

func live(version string) *Version {
	return &Version{Version: version, State: "READY_FOR_SALE"}
}

func TestDecide(t *testing.T) {
	cases := []struct {
		name     string
		report   Report
		releases []Release
		action   Action
		version  string
		build    string
		newer    string
	}{
		{
			name:     "live matches the latest release",
			report:   Report{Live: live("5.1.1"), Builds: map[string]string{"5.1.1": "400"}},
			releases: releases("v5.1.1", "v5.1.0"),
			action:   UpToDate, version: "5.1.1",
		},
		{
			name:     "live behind by several releases submits only the newest",
			report:   Report{Live: live("5.0.0"), Builds: map[string]string{"5.0.1": "390", "5.1.0": "395", "5.1.1": "400"}},
			releases: releases("v5.0.1", "v5.1.1", "v5.1.0", "v5.0.0"),
			action:   Submit, version: "5.1.1", build: "400", newer: "v5.1.1 v5.1.0 v5.0.1",
		},
		{
			name:     "the newest build has not been processed yet",
			report:   Report{Live: live("5.1.0"), Builds: map[string]string{"5.1.0": "395"}},
			releases: releases("v5.1.1", "v5.1.0"),
			action:   WaitingForBuild, version: "5.1.1", newer: "v5.1.1",
		},
		{
			name: "a version in review is never interrupted by a newer release",
			report: Report{
				Live: live("5.1.0"), InFlight: &Version{Version: "5.1.1", State: "IN_REVIEW"},
				Submission: &Submission{ID: "s1", State: "IN_REVIEW"}, Builds: map[string]string{"5.1.1": "400", "5.2.0": "410"},
			},
			releases: releases("v5.2.0", "v5.1.1", "v5.1.0"),
			action:   Wait, version: "5.2.0", newer: "v5.2.0 v5.1.1",
		},
		{
			name:     "a version waiting for review",
			report:   Report{Live: live("5.1.0"), InFlight: &Version{Version: "5.1.1", State: "WAITING_FOR_REVIEW"}, Builds: map[string]string{"5.1.1": "400"}},
			releases: releases("v5.1.1"),
			action:   Wait, version: "5.1.1", newer: "v5.1.1",
		},
		{
			name:     "an approved version waiting for Apple to release it",
			report:   Report{Live: live("5.1.0"), InFlight: &Version{Version: "5.1.1", State: "PENDING_APPLE_RELEASE"}, Builds: map[string]string{"5.1.1": "400"}},
			releases: releases("v5.1.2", "v5.1.1"),
			action:   Wait, version: "5.1.2", newer: "v5.1.2 v5.1.1",
		},
		{
			name:     "an active submission without a version state",
			report:   Report{Live: live("5.1.0"), Submission: &Submission{ID: "s2", State: "WAITING_FOR_REVIEW"}, Builds: map[string]string{"5.1.1": "400"}},
			releases: releases("v5.1.1"),
			action:   Wait, version: "5.1.1", newer: "v5.1.1",
		},
		{
			name: "a rejected version without a newer release",
			report: Report{
				Live: live("5.1.0"), InFlight: &Version{Version: "5.1.1", State: "REJECTED"},
				Submission: &Submission{ID: "s3", State: "UNRESOLVED_ISSUES"}, Builds: map[string]string{"5.1.1": "400"},
			},
			releases: releases("v5.1.1", "v5.1.0"),
			action:   Rejected, version: "5.1.1", newer: "v5.1.1",
		},
		{
			name:     "a metadata rejection",
			report:   Report{Live: live("5.1.0"), InFlight: &Version{Version: "5.1.1", State: "METADATA_REJECTED"}, Builds: map[string]string{"5.1.1": "400"}},
			releases: releases("v5.1.1"),
			action:   Rejected, version: "5.1.1", newer: "v5.1.1",
		},
		{
			name: "a newer release supersedes a rejected version",
			report: Report{
				Live: live("5.1.0"), InFlight: &Version{Version: "5.1.1", State: "REJECTED"},
				Submission: &Submission{ID: "s4", State: "UNRESOLVED_ISSUES"}, Builds: map[string]string{"5.1.1": "400", "5.1.2": "405"},
			},
			releases: releases("v5.1.2", "v5.1.1", "v5.1.0"),
			action:   Submit, version: "5.1.2", build: "405", newer: "v5.1.2 v5.1.1",
		},
		{
			name:     "a newer release supersedes a version that was never submitted",
			report:   Report{Live: live("5.1.0"), InFlight: &Version{Version: "5.1.1", State: "PREPARE_FOR_SUBMISSION"}, Builds: map[string]string{"5.1.2": "405"}},
			releases: releases("v5.1.2", "v5.1.1"),
			action:   Submit, version: "5.1.2", build: "405", newer: "v5.1.2 v5.1.1",
		},
		{
			name:     "a developer rejected version is resubmitted",
			report:   Report{Live: live("5.1.0"), InFlight: &Version{Version: "5.1.1", State: "DEVELOPER_REJECTED"}, Builds: map[string]string{"5.1.1": "400"}},
			releases: releases("v5.1.1"),
			action:   Submit, version: "5.1.1", build: "400", newer: "v5.1.1",
		},
		{
			name:     "a rejected version superseded by a release whose build is still processing",
			report:   Report{Live: live("5.1.0"), InFlight: &Version{Version: "5.1.1", State: "REJECTED"}, Builds: map[string]string{"5.1.1": "400"}},
			releases: releases("v5.1.2", "v5.1.1"),
			action:   WaitingForBuild, version: "5.1.2", newer: "v5.1.2 v5.1.1",
		},
		{
			name:     "the first App Store release",
			report:   Report{Builds: map[string]string{"1.0.0": "1"}},
			releases: releases("v1.0.0"),
			action:   Submit, version: "1.0.0", build: "1", newer: "v1.0.0",
		},
		{
			name:     "drafts, prereleases and odd tags are ignored",
			report:   Report{Live: live("5.1.0"), Builds: map[string]string{"5.1.0": "395", "6.0.0": "500"}},
			releases: []Release{{TagName: "v6.0.0", IsDraft: true}, {TagName: "v5.2.0", IsPrerelease: true}, {TagName: "nightly"}, {TagName: "v5.1.0"}},
			action:   UpToDate, version: "5.1.0",
		},
		{
			name:     "App Store Connect has a manual version newer than every release",
			report:   Report{Live: live("5.1.0"), InFlight: &Version{Version: "6.0.0", State: "PREPARE_FOR_SUBMISSION"}, Builds: map[string]string{"5.1.1": "400"}},
			releases: releases("v5.1.1"),
			action:   Wait, version: "5.1.1", newer: "v5.1.1",
		},
		{
			name:   "no releases at all",
			report: Report{Live: live("5.1.0")},
			action: UpToDate,
		},
		{
			name:     "versions compare numerically",
			report:   Report{Live: live("5.9.0"), Builds: map[string]string{"5.10.0": "600"}},
			releases: releases("v5.9.0", "v5.10.0"),
			action:   Submit, version: "5.10.0", build: "600", newer: "v5.10.0",
		},
	}
	for _, test := range cases {
		t.Run(test.name, func(t *testing.T) {
			plan := Decide(test.report, test.releases)
			if plan.Action != test.action || plan.Version != test.version || plan.Build != test.build || strings.Join(tags(plan.Releases), " ") != test.newer {
				t.Fatalf("got %+v", plan)
			}
			if plan.Reason == "" {
				t.Fatal("the plan has no reason")
			}
		})
	}
}

func TestOutputsAreGitHubOutputLines(t *testing.T) {
	plan := Decide(Report{Live: live("5.0.0"), Builds: map[string]string{"5.1.0": "395"}}, releases("v5.1.0", "v5.0.1"))
	output := plan.Outputs()
	for _, line := range []string{"action=submit", "version=5.1.0", "build=395", "live=5.0.0", "releases=v5.1.0 v5.0.1"} {
		if !strings.Contains(output, line+"\n") {
			t.Errorf("missing %q in\n%s", line, output)
		}
	}
	if plan.Summary() != "submit 5.1.0 395" {
		t.Fatalf("unexpected summary %q", plan.Summary())
	}
}

func TestParseReportAndReleases(t *testing.T) {
	report, err := ParseReport([]byte(`{"live":{"version":"5.1.0","state":"READY_FOR_SALE"},"inFlight":null,"submission":null,"builds":{"5.1.1":"400"}}`))
	if err != nil || report.Live.Version != "5.1.0" || report.InFlight != nil || report.Builds["5.1.1"] != "400" {
		t.Fatalf("unexpected report %+v, %v", report, err)
	}
	list, err := ParseReleases([]byte(`[{"tagName":"v5.1.1","isDraft":false,"isPrerelease":false}]`))
	if err != nil || len(list) != 1 || list[0].TagName != "v5.1.1" {
		t.Fatalf("unexpected releases %+v, %v", list, err)
	}
	if _, err := ParseReport([]byte(`nope`)); err == nil {
		t.Fatal("invalid JSON was accepted")
	}
}
