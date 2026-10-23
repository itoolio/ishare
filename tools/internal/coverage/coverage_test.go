package coverage

import (
	"math"
	"strings"
	"testing"
)

const sample = `{
  "coveredLines": 0, "executableLines": 0, "lineCoverage": 0,
  "targets": [
    {"name": "ishare.app", "files": [
      {"path": "/repo/ishare/Capture/CaptureSession.swift", "name": "CaptureSession.swift", "coveredLines": 30, "executableLines": 100},
      {"path": "/repo/ishare/Capture/Recording/Recorder.swift", "name": "Recorder.swift", "coveredLines": 5, "executableLines": 50},
      {"path": "/repo/ishare/Http/UploadService.swift", "name": "UploadService.swift", "coveredLines": 80, "executableLines": 100},
      {"path": "/repo/ishare/Http/ResponseTemplate.swift", "name": "ResponseTemplate.swift", "coveredLines": 45, "executableLines": 50},
      {"path": "/repo/ishare/Util/CustomUploader.swift", "name": "CustomUploader.swift", "coveredLines": 40, "executableLines": 50},
      {"path": "/repo/ishare/Views/Editor/Canvas.swift", "name": "Canvas.swift", "coveredLines": 10, "executableLines": 20},
      {"path": "/repo/ishare/Views/HistoryWindow.swift", "name": "HistoryWindow.swift", "coveredLines": 0, "executableLines": 30},
      {"path": "/repo/ishare/App.swift", "name": "App.swift", "coveredLines": 1, "executableLines": 2}
    ]},
    {"name": "ishareWidgets.appex", "files": [
      {"path": "/repo/ishareWidgets/Widget.swift", "name": "Widget.swift", "coveredLines": 0, "executableLines": 10}
    ]},
    {"name": "ishareTests.xctest", "files": [
      {"path": "/repo/ishareTests/CaptureTests.swift", "name": "CaptureTests.swift", "coveredLines": 500, "executableLines": 500}
    ]},
    {"name": "Alamofire", "files": [
      {"path": "/repo/build/SourcePackages/checkouts/Alamofire/Source/Session.swift", "name": "Session.swift", "coveredLines": 1, "executableLines": 1000}
    ]}
  ]
}`

func parsed(t *testing.T) Report {
	t.Helper()
	report, err := Parse(strings.NewReader(sample))
	if err != nil {
		t.Fatal(err)
	}
	return report
}

func byName(areas []Area) map[string]Area {
	result := map[string]Area{}
	for _, area := range areas {
		result[area.Name] = area
	}
	return result
}

func TestParseRejectsInvalidReports(t *testing.T) {
	if _, err := Parse(strings.NewReader("not json")); err == nil {
		t.Fatal("expected an error for invalid JSON")
	}
	if _, err := Parse(strings.NewReader(`{"targets": []}`)); err == nil {
		t.Fatal("expected an error for a report without targets")
	}
}

func TestClassify(t *testing.T) {
	cases := map[string]string{
		"ishare/Capture/CaptureSession.swift":      "Capture",
		"ishare/Capture/Recording/Recorder.swift":  "Recording",
		"ishare/Http/Upload.swift":                 "Http",
		"ishare/Http/ResponseTemplate.swift":       "ISCU",
		"ishare/Util/IscuImport.swift":             "ISCU",
		"ishare/Util/Log.swift":                    "Util",
		"ishare/Views/Editor/Tools/Arrow.swift":    "Editor",
		"ishare/Views/Settings/SettingsView.swift": "Views",
		"ishare/App.swift":                         "App",
		"ishareWidgets/RecentUploads.swift":        "Widgets",
		"sharemenuext/ShareViewController.swift":   "Share Extension",
		"Elsewhere.swift":                          "Other",
		"/outside/the/repo/ishare/Capture/X.swift": "outside",
	}
	for path, want := range cases {
		if got := Classify(path); got != want {
			t.Errorf("Classify(%q) = %q, want %q", path, got, want)
		}
	}
}

func TestRelativeStripsTheRoot(t *testing.T) {
	if got := Relative("/repo/ishare/Http/Upload.swift", "/repo"); got != "ishare/Http/Upload.swift" {
		t.Errorf("got %q", got)
	}
	if got := Relative("/elsewhere/file.swift", "/repo"); got != "/elsewhere/file.swift" {
		t.Errorf("got %q", got)
	}
}

func TestSummarizeGroupsAppFilesByArea(t *testing.T) {
	areas := byName(Summarize(parsed(t), "/repo", DefaultTargets))
	expect := map[string][2]int{
		"Capture":   {30, 100},
		"Recording": {5, 50},
		"Http":      {80, 100},
		"ISCU":      {85, 100},
		"Editor":    {10, 20},
		"Views":     {0, 30},
		"App":       {1, 2},
		"Widgets":   {0, 10},
	}
	if len(areas) != len(expect) {
		t.Fatalf("got areas %v", areas)
	}
	for name, lines := range expect {
		area := areas[name]
		if area.Covered != lines[0] || area.Executable != lines[1] {
			t.Errorf("%s: got %d/%d, want %d/%d", name, area.Covered, area.Executable, lines[0], lines[1])
		}
	}
	if math.Abs(areas["ISCU"].Percent()-85) > 0.001 {
		t.Errorf("ISCU percent %f", areas["ISCU"].Percent())
	}
	total := Total(Summarize(parsed(t), "/repo", DefaultTargets))
	if total.Covered != 211 || total.Executable != 412 || total.Files != 9 {
		t.Errorf("total %+v", total)
	}
}

func TestParseMinimum(t *testing.T) {
	minimum, err := ParseMinimum("Http=72.5")
	if err != nil || minimum.Area != "Http" || minimum.Percent != 72.5 {
		t.Fatalf("got %+v, %v", minimum, err)
	}
	if minimum, err := ParseMinimum(" Share Extension = 10% "); err != nil || minimum.Area != "Share Extension" || minimum.Percent != 10 {
		t.Fatalf("got %+v, %v", minimum, err)
	}
	for _, invalid := range []string{"Http", "=50", "Http=abc", "Http=101", "Http=-1"} {
		if _, err := ParseMinimum(invalid); err == nil {
			t.Errorf("%q should be rejected", invalid)
		}
	}
}

func TestCheckReportsAreasBelowTheirMinimum(t *testing.T) {
	areas := Summarize(parsed(t), "/repo", DefaultTargets)
	minimums := []Minimum{{"Capture", 25}, {"Http", 80}, {"ISCU", 86}, {"Total", 55}, {"Missing", 1}}
	violations := Check(areas, minimums)
	got := map[string]Violation{}
	for _, violation := range violations {
		got[violation.Minimum.Area] = violation
	}
	if len(violations) != 3 {
		t.Fatalf("got violations %v", violations)
	}
	if got["ISCU"].Actual != 85 || got["ISCU"].Missing {
		t.Errorf("ISCU violation %+v", got["ISCU"])
	}
	if !got["Missing"].Missing {
		t.Errorf("missing area should be reported as missing")
	}
	if _, ok := got["Total"]; !ok {
		t.Errorf("total below 55%% should fail")
	}
	if !strings.Contains(got["ISCU"].String(), "85.0%, below the minimum of 86.0%") {
		t.Errorf("message %q", got["ISCU"].String())
	}
}

func TestCheckRoundsToOneDecimalBeforeComparing(t *testing.T) {
	areas := []Area{{Name: "Http", Covered: 7496, Executable: 10000}}
	if violations := Check(areas, []Minimum{{"Http", 75}}); len(violations) != 0 {
		t.Fatalf("74.96%% rounds to 75.0%% and should pass, got %v", violations)
	}
	if violations := Check(areas, []Minimum{{"Http", 75.1}}); len(violations) != 1 {
		t.Fatalf("expected a violation, got %v", violations)
	}
}

func TestMarkdownListsEveryAreaAndTheOutcome(t *testing.T) {
	areas := Summarize(parsed(t), "/repo", DefaultTargets)
	minimums := []Minimum{{"Capture", 25}, {"ISCU", 90}}
	markdown := Markdown(areas, minimums, Check(areas, minimums))
	for _, want := range []string{
		Heading,
		"| Capture | 1 | 30 / 100 | 30.0% | 25.0% met |",
		"| ISCU | 2 | 85 / 100 | 85.0% | 90.0% below |",
		"| Views | 1 | 0 / 30 | 0.0% |  |",
		"| **Total** | 9 | 211 / 412 | **51.2%** |  |",
		"- ISCU coverage is 85.0%, below the minimum of 90.0%",
	} {
		if !strings.Contains(markdown, want) {
			t.Errorf("markdown is missing %q:\n%s", want, markdown)
		}
	}
	if !strings.HasPrefix(markdown, Heading+"\n") {
		t.Errorf("markdown should start with the heading")
	}
	passing := Markdown(areas, nil, nil)
	if !strings.Contains(passing, "Every coverage minimum is met.") {
		t.Errorf("passing markdown %q", passing)
	}
}
