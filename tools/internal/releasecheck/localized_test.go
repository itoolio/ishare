package releasecheck

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func writeScreenshots(t *testing.T, root, locale string, names ...string) {
	t.Helper()
	directory := filepath.Join(root, locale)
	if err := os.MkdirAll(directory, 0o755); err != nil {
		t.Fatal(err)
	}
	for _, name := range names {
		if err := os.WriteFile(filepath.Join(directory, name), nil, 0o644); err != nil {
			t.Fatal(err)
		}
	}
}

func TestLocalizedScreenshots(t *testing.T) {
	root := t.TempDir()
	writeScreenshots(t, root, "en-US", "01_menu.jpg", "02_editor.jpg")
	writeScreenshots(t, root, "de-DE", "01_menu.jpg", "02_editor.jpg")
	result := LocalizedScreenshotsResult(root)
	if len(result.Problems) != 0 || !strings.Contains(result.Skipped, "zh-Hans") || strings.Contains(result.Skipped, "de-DE") {
		t.Fatalf("unexpected result %+v", result)
	}

	writeScreenshots(t, root, "ja", "01_menu.jpg")
	writeScreenshots(t, root, "pt-BR", "01_menu.jpg", "02_editor.jpg")
	result = LocalizedScreenshotsResult(root)
	problems := strings.Join(result.Problems, "\n")
	if !strings.Contains(problems, "ja has the screenshots 01_menu.jpg, en-US has 01_menu.jpg, 02_editor.jpg") || !strings.Contains(problems, "pt-BR is not one of the supported") {
		t.Fatalf("unexpected problems %q", problems)
	}
}
