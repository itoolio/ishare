package buildlog

import (
	"bytes"
	"reflect"
	"strings"
	"testing"
)

const sample = `CompileSwift normal arm64 /repo/ishare/App.swift (in target 'ishare' from project 'ishare')
/repo/ishare/App.swift:12:5: warning: variable 'x' was never mutated; consider changing to 'let' constant
    |     |- warning: variable 'x' was never mutated; consider changing to 'let' constant
/repo/ishare/App.swift:12:5: warning: variable 'x' was never mutated; consider changing to 'let' constant
/repo/build/SourcePackages/checkouts/Defaults/Sources/Defaults.swift:3:1: warning: deprecated
2026-10-23 13:11:07.409 appintentsmetadataprocessor[1:2] warning: Metadata extraction skipped, no AppIntents.framework dependency found
--- xcodebuild: WARNING: Using the first of multiple matching destinations:
ld: warning: ignoring duplicate libraries: '-lc++'
note: Building targets in dependency order
2026-10-23 14:02:08.301192+0200 ishare[1:2] [Sparkle] Warning: Background app automatically schedules for update checks
** BUILD SUCCEEDED **
`

func TestWarningsKeepsUniqueTopLevelProjectWarnings(t *testing.T) {
	got, err := Warnings(strings.NewReader(sample), DefaultIgnored)
	if err != nil {
		t.Fatal(err)
	}
	want := []string{
		"/repo/ishare/App.swift:12:5: warning: variable 'x' was never mutated; consider changing to 'let' constant",
		"2026-10-23 13:11:07.409 appintentsmetadataprocessor[1:2] warning: Metadata extraction skipped, no AppIntents.framework dependency found",
		"--- xcodebuild: WARNING: Using the first of multiple matching destinations:",
		"ld: warning: ignoring duplicate libraries: '-lc++'",
	}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("unexpected warnings:\n%q", got)
	}
}

func TestWarningsHonoursExtraIgnoredFragments(t *testing.T) {
	got, err := Warnings(strings.NewReader(sample), append(DefaultIgnored, "appintentsmetadataprocessor", "xcodebuild:", "ld:", "/repo/ishare/"))
	if err != nil {
		t.Fatal(err)
	}
	if len(got) != 0 {
		t.Fatalf("expected no warnings, got %q", got)
	}
}

func TestCheckAnnotatesEveryWarningAndCountsThem(t *testing.T) {
	var output bytes.Buffer
	logs := []Log{
		{Name: "clean.log", Reader: strings.NewReader("** BUILD SUCCEEDED **\n")},
		{Name: "app.log", Reader: strings.NewReader("/repo/a.swift:1:1: warning: unused\n")},
	}
	count, err := Check(logs, DefaultIgnored, &output)
	if err != nil {
		t.Fatal(err)
	}
	if count != 1 || output.String() != "::error title=Build warning in app.log::/repo/a.swift:1:1: warning: unused\n" {
		t.Fatalf("count %d, output %q", count, output.String())
	}
}
