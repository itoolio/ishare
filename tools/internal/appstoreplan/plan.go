package appstoreplan

import (
	"encoding/json"
	"fmt"
	"sort"
	"strconv"
	"strings"
)

type Version struct {
	Version string `json:"version"`
	State   string `json:"state"`
}

type Submission struct {
	ID    string `json:"id"`
	State string `json:"state"`
}

type Report struct {
	Live       *Version          `json:"live"`
	InFlight   *Version          `json:"inFlight"`
	Submission *Submission       `json:"submission"`
	Builds     map[string]string `json:"builds"`
}

type Release struct {
	TagName      string `json:"tagName"`
	IsDraft      bool   `json:"isDraft"`
	IsPrerelease bool   `json:"isPrerelease"`
}

type Action string

const (
	Wait            Action = "wait"
	UpToDate        Action = "up-to-date"
	Submit          Action = "submit"
	WaitingForBuild Action = "waiting-for-build"
	Rejected        Action = "rejected"
)

type Plan struct {
	Action   Action
	Version  string
	Build    string
	Live     string
	Releases []string
	Reason   string
}

var activeVersionStates = map[string]bool{
	"WAITING_FOR_REVIEW":            true,
	"IN_REVIEW":                     true,
	"PENDING_APPLE_RELEASE":         true,
	"PENDING_DEVELOPER_RELEASE":     true,
	"PROCESSING_FOR_APP_STORE":      true,
	"PROCESSING_FOR_DISTRIBUTION":   true,
	"WAITING_FOR_EXPORT_COMPLIANCE": true,
	"ACCEPTED":                      true,
	"PENDING_CONTRACT":              true,
}

var activeSubmissionStates = map[string]bool{
	"WAITING_FOR_REVIEW": true,
	"IN_REVIEW":          true,
	"CANCELING":          true,
	"COMPLETING":         true,
}

var rejectedVersionStates = map[string]bool{
	"REJECTED":          true,
	"METADATA_REJECTED": true,
	"INVALID_BINARY":    true,
}

func ParseReport(data []byte) (Report, error) {
	var report Report
	if err := json.Unmarshal(data, &report); err != nil {
		return Report{}, fmt.Errorf("the App Store status report is not valid JSON: %w", err)
	}
	return report, nil
}

func ParseReleases(data []byte) ([]Release, error) {
	var releases []Release
	if err := json.Unmarshal(data, &releases); err != nil {
		return nil, fmt.Errorf("the release list is not valid JSON: %w", err)
	}
	return releases, nil
}

func Decide(report Report, releases []Release) Plan {
	versions := publishedVersions(releases)
	plan := Plan{}
	if report.Live != nil {
		plan.Live = report.Live.Version
	}
	plan.Releases = newerThan(versions, plan.Live)
	if len(versions) > 0 {
		plan.Version = versions[0]
	}
	if inFlight := report.InFlight; inFlight != nil && activeVersionStates[inFlight.State] {
		return withReason(plan, Wait, fmt.Sprintf("%s is %s; an active review is never interrupted", inFlight.Version, inFlight.State))
	}
	if submission := report.Submission; submission != nil && activeSubmissionStates[submission.State] {
		return withReason(plan, Wait, fmt.Sprintf("review submission %s is %s", submission.ID, submission.State))
	}
	if len(versions) == 0 {
		return withReason(plan, UpToDate, "there are no published GitHub releases")
	}
	latest := versions[0]
	if inFlight := report.InFlight; inFlight != nil && rejectedVersionStates[inFlight.State] && Compare(latest, inFlight.Version) <= 0 {
		plan.Version = inFlight.Version
		return withReason(plan, Rejected, fmt.Sprintf("%s is %s and no newer release exists", inFlight.Version, inFlight.State))
	}
	if inFlight := report.InFlight; inFlight != nil && Compare(inFlight.Version, latest) > 0 {
		return withReason(plan, Wait, fmt.Sprintf("App Store Connect has %s (%s), which is newer than the latest release %s", inFlight.Version, inFlight.State, latest))
	}
	if plan.Live != "" && Compare(latest, plan.Live) <= 0 {
		return withReason(plan, UpToDate, fmt.Sprintf("%s is live", plan.Live))
	}
	build, processed := report.Builds[latest]
	if !processed || build == "" {
		return withReason(plan, WaitingForBuild, fmt.Sprintf("the build for %s has not finished processing", latest))
	}
	plan.Build = build
	reason := fmt.Sprintf("%s (%s) is the newest processed release", latest, build)
	if inFlight := report.InFlight; inFlight != nil && inFlight.Version != latest {
		reason += fmt.Sprintf(" and supersedes %s (%s)", inFlight.Version, inFlight.State)
	}
	return withReason(plan, Submit, reason)
}

func withReason(plan Plan, action Action, reason string) Plan {
	plan.Action = action
	plan.Reason = reason
	if action != Submit {
		plan.Build = ""
	}
	return plan
}

func (plan Plan) Outputs() string {
	lines := []string{
		"action=" + string(plan.Action),
		"version=" + plan.Version,
		"build=" + plan.Build,
		"live=" + plan.Live,
		"releases=" + strings.Join(tags(plan.Releases), " "),
		"reason=" + strings.ReplaceAll(plan.Reason, "\n", " "),
	}
	return strings.Join(lines, "\n") + "\n"
}

func (plan Plan) Summary() string {
	switch plan.Action {
	case Submit:
		return fmt.Sprintf("submit %s %s", plan.Version, plan.Build)
	case WaitingForBuild, Rejected:
		return fmt.Sprintf("%s %s", plan.Action, plan.Version)
	default:
		return string(plan.Action)
	}
}

func tags(versions []string) []string {
	result := make([]string, len(versions))
	for index, version := range versions {
		result[index] = "v" + version
	}
	return result
}

func publishedVersions(releases []Release) []string {
	seen := map[string]bool{}
	var versions []string
	for _, release := range releases {
		version := strings.TrimPrefix(release.TagName, "v")
		if release.IsDraft || release.IsPrerelease || !valid(version) || seen[version] {
			continue
		}
		seen[version] = true
		versions = append(versions, version)
	}
	sort.SliceStable(versions, func(left, right int) bool { return Compare(versions[left], versions[right]) > 0 })
	return versions
}

func newerThan(versions []string, live string) []string {
	var result []string
	for _, version := range versions {
		if live == "" || Compare(version, live) > 0 {
			result = append(result, version)
		}
	}
	return result
}

func valid(version string) bool {
	_, ok := parse(version)
	return ok
}

func parse(version string) ([]int, bool) {
	parts := strings.Split(version, ".")
	if len(parts) == 0 || len(parts) > 3 {
		return nil, false
	}
	numbers := make([]int, 3)
	for index, part := range parts {
		number, err := strconv.Atoi(part)
		if err != nil || number < 0 {
			return nil, false
		}
		numbers[index] = number
	}
	return numbers, true
}

func Compare(left, right string) int {
	a, okA := parse(left)
	b, okB := parse(right)
	if !okA || !okB {
		return strings.Compare(left, right)
	}
	for index := range a {
		if a[index] != b[index] {
			if a[index] < b[index] {
				return -1
			}
			return 1
		}
	}
	return 0
}
