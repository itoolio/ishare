package version

import (
	"os"
	"testing"

	"github.com/itoolio/ishare/tools/internal/repo"
)

func TestApplyReplacesBothLines(t *testing.T) {
	config := []byte("// header\nMARKETING_VERSION = 4.2.6\nCURRENT_PROJECT_VERSION = 120\nOTHER = 1\n")
	got, err := Apply(config, "5.0.0", "321")
	if err != nil {
		t.Fatal(err)
	}
	want := "// header\nMARKETING_VERSION = 5.0.0\nCURRENT_PROJECT_VERSION = 321\nOTHER = 1\n"
	if string(got) != want {
		t.Fatalf("unexpected config:\n%s", got)
	}
}

func TestApplyRejectsMissingLines(t *testing.T) {
	if _, err := Apply([]byte("MARKETING_VERSION = 1.0.0\n"), "5.0.0", "1"); err == nil {
		t.Fatal("expected an error")
	}
}

func TestApplyRejectsInvalidVersions(t *testing.T) {
	for _, candidate := range []string{"", "5", "5.0", "v5.0.0", "5.0.0 $(rm)"} {
		if _, err := Apply([]byte("MARKETING_VERSION = 1\nCURRENT_PROJECT_VERSION = 1\n"), candidate, "1"); err == nil {
			t.Errorf("expected %q to be rejected", candidate)
		}
	}
	if _, err := Apply([]byte("MARKETING_VERSION = 1\nCURRENT_PROJECT_VERSION = 1\n"), "5.1.0-beta.1", "1"); err != nil {
		t.Errorf("expected a prerelease version to be accepted: %v", err)
	}
}

func TestRepositoryConfigCanBeUpdated(t *testing.T) {
	config, err := os.ReadFile(repo.Path("Config.xcconfig"))
	if err != nil {
		t.Fatal(err)
	}
	if _, err := Apply(config, "9.9.9", "1"); err != nil {
		t.Fatal(err)
	}
}
