package metadata

import (
	"bytes"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/itoolio/ishare/tools/internal/repo"
)

const sampleCatalog = `{
  "sourceLanguage" : "en",
  "strings" : {
    "Add uploader presets" : {
      "localizations" : {
        "de" : { "stringUnit" : { "state" : "translated", "value" : "Upload-Voreinstellungen hinzufügen" } }
      }
    },
    "description" : {
      "localizations" : {
        "de" : { "stringUnit" : { "state" : "translated", "value" : "Beschreibung" } },
        "en" : { "stringUnit" : { "state" : "translated", "value" : "Description" } }
      }
    },
    "name" : {
      "localizations" : {
        "de" : { "stringUnit" : { "state" : "translated", "value" : "ishare - Bildschirmaufnahme" } },
        "en" : { "stringUnit" : { "state" : "translated", "value" : "ishare - screen capture" } }
      }
    },
    "release_notes.fallback" : {
      "localizations" : {
        "de" : { "stringUnit" : { "state" : "translated", "value" : "Fehlerbehebungen und Verbesserungen." } },
        "en" : { "stringUnit" : { "state" : "translated", "value" : "Bug fixes and improvements." } }
      }
    },
    "release_notes.heading.features" : {
      "localizations" : {
        "de" : { "stringUnit" : { "state" : "translated", "value" : "Neue Funktionen" } },
        "en" : { "stringUnit" : { "state" : "translated", "value" : "Features" } }
      }
    }
  },
  "version" : "1.0"
}`

func catalog(t *testing.T) Catalog {
	t.Helper()
	parsed, err := ParseCatalog([]byte(sampleCatalog))
	if err != nil {
		t.Fatal(err)
	}
	return parsed
}

func TestLocalizeReleaseNotes(t *testing.T) {
	notes := "Features:\n• Add uploader presets\n• Record the webcam\n\nBug Fixes:\n• Fix a crash"
	got := LocalizeReleaseNotes(notes, catalog(t), "de")
	want := "Neue Funktionen:\n• Upload-Voreinstellungen hinzufügen\n• Record the webcam\n\nBug Fixes:\n• Fix a crash"
	if got != want {
		t.Fatalf("got\n%s\nwant\n%s", got, want)
	}
	if got := LocalizeReleaseNotes("Bug fixes and improvements.", catalog(t), "de"); got != "Fehlerbehebungen und Verbesserungen." {
		t.Fatalf("unexpected fallback %q", got)
	}
}

func TestRenderFallsBackToEnglish(t *testing.T) {
	rendered := Render(Input{Catalog: catalog(t), Copied: Files{"support_url.txt": "https://example.com\n"}, ReleaseNotes: "Features:\n• Something"})
	german := rendered.Locales["de-DE"]
	if german["name.txt"] != "ishare - Bildschirmaufnahme\n" || german["support_url.txt"] != "https://example.com\n" || german["release_notes.txt"] != "Neue Funktionen:\n• Something\n" {
		t.Fatalf("unexpected German files %v", german)
	}
	if _, ok := rendered.Locales["en-US"]["release_notes.txt"]; ok {
		t.Fatal("the English release notes are the input and must not be rewritten")
	}
	if rendered.Locales["ja"]["name.txt"] != "ishare - screen capture\n" {
		t.Fatalf("a missing translation did not fall back to English: %v", rendered.Locales["ja"])
	}
	if !strings.Contains(strings.Join(rendered.Fallbacks, " "), "ja/name") {
		t.Fatalf("the fallback was not reported: %v", rendered.Fallbacks)
	}
}

func TestProblems(t *testing.T) {
	files := Files{
		"name.txt":             strings.Repeat("あ", 31),
		"subtitle.txt":         "fine",
		"keywords.txt":         "screenshot,スクリーンショット,スクリーンショット,," + strings.Repeat("録", 30),
		"promotional_text.txt": "one\ntwo",
		"description.txt":      "ok",
	}
	problems := strings.Join(Problems("ja", files), "\n")
	for _, expected := range []string{"name.txt is 31 characters", "keywords.txt is", "bytes long", "repeats", "empty keyword", "promotional_text.txt must be a single line"} {
		if !strings.Contains(problems, expected) {
			t.Errorf("missing %q in\n%s", expected, problems)
		}
	}
	if problems := Problems("de-DE", Files{"name.txt": "ishare", "description.txt": "x", "keywords.txt": strings.Repeat("ü", 50)}); len(problems) != 0 {
		t.Fatalf("100 bytes of keywords were rejected: %v", problems)
	}
	if problems := Problems("de-DE", Files{}); len(problems) != 2 {
		t.Fatalf("missing required files were not reported: %v", problems)
	}
}

func TestCommittedMetadataMatchesTheCatalog(t *testing.T) {
	var output bytes.Buffer
	if err := Run(Options{Directory: repo.Path("fastlane", "metadata"), Check: true, Output: &output}); err != nil {
		t.Fatal(err)
	}
}

func TestRunWritesEveryLocale(t *testing.T) {
	directory := t.TempDir()
	if err := os.WriteFile(filepath.Join(directory, CatalogName), []byte(sampleCatalog), 0o644); err != nil {
		t.Fatal(err)
	}
	source := filepath.Join(directory, "en-US")
	if err := os.MkdirAll(source, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(source, ReleaseNotesFile), []byte("Features:\n• Add uploader presets\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	var output bytes.Buffer
	if err := Run(Options{Directory: directory, Output: &output}); err != nil {
		t.Fatal(err)
	}
	notes, err := os.ReadFile(filepath.Join(directory, "de-DE", ReleaseNotesFile))
	if err != nil || string(notes) != "Neue Funktionen:\n• Upload-Voreinstellungen hinzufügen\n" {
		t.Fatalf("unexpected German release notes %q, %v", notes, err)
	}
	if _, err := os.Stat(filepath.Join(directory, "zh-Hans", "name.txt")); err != nil {
		t.Fatal(err)
	}
	if err := Run(Options{Directory: directory, Check: true, Output: &output}); err != nil {
		t.Fatalf("the freshly written metadata is reported as stale: %v", err)
	}
	if err := os.WriteFile(filepath.Join(directory, "de-DE", "name.txt"), []byte("stale\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := Run(Options{Directory: directory, Check: true, Output: &output}); err == nil || !strings.Contains(err.Error(), "de-DE/name.txt") {
		t.Fatalf("stale metadata was not reported: %v", err)
	}
}
