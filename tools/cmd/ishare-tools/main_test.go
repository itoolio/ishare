package main

import (
	"bytes"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/itoolio/ishare/tools/internal/repo"
)

func execute(t *testing.T, stdin string, arguments ...string) (int, string, string) {
	t.Helper()
	var stdout, stderr bytes.Buffer
	code := run(arguments, environment{stdin: strings.NewReader(stdin), stdout: &stdout}, &stderr)
	return code, stdout.String(), stderr.String()
}

func TestUsageListsEveryCommand(t *testing.T) {
	code, _, stderr := execute(t, "")
	if code != 2 {
		t.Fatalf("exit code %d", code)
	}
	for name := range commands {
		if !strings.Contains(stderr, name) {
			t.Errorf("usage does not mention %s", name)
		}
	}
}

func TestUnknownCommandFails(t *testing.T) {
	if code, _, stderr := execute(t, "", "deploy"); code != 2 || !strings.Contains(stderr, `unknown command "deploy"`) {
		t.Fatalf("exit code %d, stderr %q", code, stderr)
	}
}

func TestWrongArgumentCountPrintsCommandUsage(t *testing.T) {
	for _, arguments := range [][]string{{"set-version"}, {"merge-translations", "a"}, {"release-notes", "a", "b"}} {
		code, _, stderr := execute(t, "", arguments...)
		if code != 2 || !strings.HasPrefix(stderr, "usage: ishare-tools "+arguments[0]) {
			t.Errorf("%v: exit code %d, stderr %q", arguments, code, stderr)
		}
	}
}

func TestReleaseNotesWritesToStdoutAndFiles(t *testing.T) {
	markdown := "## 1.0.0\n\n### Features\n\n* **menu:** add a GIF switch ([abcdef1](https://example.com))\n"
	code, stdout, _ := execute(t, markdown, "release-notes")
	if code != 0 || stdout != "Features:\n• Add a GIF switch\n" {
		t.Fatalf("exit code %d, stdout %q", code, stdout)
	}
	output := filepath.Join(t.TempDir(), "notes.txt")
	if code, _, stderr := execute(t, "", "release-notes", output); code != 0 {
		t.Fatalf("exit code %d, stderr %q", code, stderr)
	}
	if data, _ := os.ReadFile(output); string(data) != "Bug fixes and improvements.\n" {
		t.Fatalf("unexpected file %q", data)
	}
}

func TestMergeTranslationsRoundTripsTheCatalog(t *testing.T) {
	catalog := repo.Path("ishare", "Localizable.xcstrings")
	output := filepath.Join(t.TempDir(), "merged.xcstrings")
	code, stdout, stderr := execute(t, "", "merge-translations", catalog, catalog, output)
	if code != 0 {
		t.Fatalf("exit code %d, stderr %q", code, stderr)
	}
	if stdout != "added=0\nlanguages=\n" {
		t.Fatalf("unexpected output %q", stdout)
	}
	original, _ := os.ReadFile(catalog)
	merged, _ := os.ReadFile(output)
	if !bytes.Equal(original, merged) {
		t.Fatal("the merged catalog differs from the original")
	}
}

func TestRegisterBundleIDNeedsCredentials(t *testing.T) {
	t.Setenv("KEY_ID", "")
	t.Setenv("ISSUER_ID", "")
	t.Setenv("PRIVATE_KEY_BASE64", "")
	if code, _, stderr := execute(t, "", "register-bundle-id", "dev.adrian.ishare"); code != 1 || !strings.Contains(stderr, "KEY_ID") {
		t.Fatalf("exit code %d, stderr %q", code, stderr)
	}
}

func TestScreenshotsRejectsInvalidLocales(t *testing.T) {
	if code, _, _ := execute(t, "", "screenshots", "../en"); code != 1 {
		t.Fatalf("exit code %d", code)
	}
}

func TestAppStorePlanPrintsOutputs(t *testing.T) {
	directory := t.TempDir()
	report := filepath.Join(directory, "status.json")
	releases := filepath.Join(directory, "releases.json")
	os.WriteFile(report, []byte(`{"live":{"version":"5.1.0","state":"READY_FOR_SALE"},"builds":{"5.1.1":"400"}}`), 0o644)
	os.WriteFile(releases, []byte(`[{"tagName":"v5.1.1"},{"tagName":"v5.1.0"}]`), 0o644)
	code, stdout, stderr := execute(t, "", "app-store-plan", "--report", report, "--releases", releases)
	if code != 0 || !strings.HasPrefix(stdout, "action=submit\nversion=5.1.1\nbuild=400\n") {
		t.Fatalf("exit code %d, stdout %q, stderr %q", code, stdout, stderr)
	}
	if code, _, _ := execute(t, "", "app-store-plan", "--report", report); code != 2 {
		t.Fatalf("missing --releases exited with %d", code)
	}
}

func TestCoverageWritesTheSummaryAndEnforcesMinimums(t *testing.T) {
	directory := t.TempDir()
	report := filepath.Join(directory, "coverage.json")
	json := `{"targets":[{"name":"ishare.app","files":[{"path":"/repo/ishare/Http/Upload.swift","coveredLines":3,"executableLines":4}]}]}`
	if err := os.WriteFile(report, []byte(json), 0o644); err != nil {
		t.Fatal(err)
	}
	summary := filepath.Join(directory, "summary.md")
	output := filepath.Join(directory, "comment.md")
	code, stdout, stderr := execute(t, "", "coverage", "--root", "/repo", "--min", "Http=70", "--output", output, "--summary-file", summary, report)
	if code != 0 || !strings.Contains(stdout, "| Http | 1 | 3 / 4 | 75.0% | 70.0% met |") {
		t.Fatalf("exit code %d, stdout %q, stderr %q", code, stdout, stderr)
	}
	for _, path := range []string{summary, output} {
		if data, _ := os.ReadFile(path); !strings.Contains(string(data), "### Code coverage") {
			t.Errorf("%s was not written: %q", path, data)
		}
	}
	code, _, stderr = execute(t, "", "coverage", "--root", "/repo", "--min", "Http=80", "--summary-file", "", report)
	if code != 1 || !strings.Contains(stderr, "1 coverage minimums not met") {
		t.Fatalf("exit code %d, stderr %q", code, stderr)
	}
	if code, _, _ := execute(t, "", "coverage", "--summary-file", "", "--min", "Http", report); code != 1 {
		t.Fatalf("an invalid minimum should fail, got %d", code)
	}
}

func TestSymbolicateNeedsACrashReportAndDSYMs(t *testing.T) {
	for _, arguments := range [][]string{{"symbolicate"}, {"symbolicate", "crash.ips"}, {"symbolicate", "--dsyms", "d.zip"}} {
		if code, _, stderr := execute(t, "", arguments...); code != 2 || !strings.HasPrefix(stderr, "usage: ishare-tools symbolicate") {
			t.Errorf("%v: exit code %d, stderr %q", arguments, code, stderr)
		}
	}
}

func TestSBOMWritesAnSPDXDocumentForTheRepository(t *testing.T) {
	output := filepath.Join(t.TempDir(), "ishare-5.5.0-sbom.spdx.json")
	code, stdout, stderr := execute(t, "", "sbom", "--version", "5.5.0", "--created", "2026-10-25T00:00:00Z",
		"--package-resolved", repo.Path("tools", "internal", "sbom", "testdata", "Package.resolved.v3"),
		"--package-dir", repo.Path("Packages", "ishareCore"),
		"--go-mod", repo.Path("tools", "go.mod"),
		"--output", output)
	if code != 0 {
		t.Fatalf("exit code %d, stderr %q", code, stderr)
	}
	if !strings.Contains(stdout, "with 6 packages") {
		t.Errorf("unexpected stdout %q", stdout)
	}
	data, err := os.ReadFile(output)
	if err != nil {
		t.Fatal(err)
	}
	for _, fragment := range []string{`"spdxVersion": "SPDX-2.3"`, `"name": "ishareCore"`, `pkg:golang/github.com/itoolio/ishare/tools@v5.5.0`, `"created": "2026-10-25T00:00:00Z"`} {
		if !strings.Contains(string(data), fragment) {
			t.Errorf("the SBOM lacks %s", fragment)
		}
	}
}

func TestSBOMRequiresAVersionAndOutput(t *testing.T) {
	for _, arguments := range [][]string{{"sbom"}, {"sbom", "--version", "1.0.0"}, {"sbom", "--output", "x.json"}} {
		if code, _, stderr := execute(t, "", arguments...); code != 2 || !strings.HasPrefix(stderr, "usage: ishare-tools sbom") {
			t.Errorf("%v: exit code %d, stderr %q", arguments, code, stderr)
		}
	}
}

func TestAutomationRequiresTheApp(t *testing.T) {
	for _, arguments := range [][]string{{"automation"}, {"automation", "--app", "x.app", "extra"}, {"automation", "--app", "x.app", "--ready-timeout", "0"}} {
		if code, _, stderr := execute(t, "", arguments...); code != 2 || !strings.HasPrefix(stderr, "usage: ishare-tools automation") {
			t.Errorf("%v: exit code %d, stderr %q", arguments, code, stderr)
		}
	}
}

func TestGuideClipsRejectsUnknownScenes(t *testing.T) {
	if code, _, stderr := execute(t, "", "guide-clips", "teleport"); code != 1 || !strings.Contains(stderr, "not a guide scene") {
		t.Fatalf("exit code %d, stderr %q", code, stderr)
	}
}
