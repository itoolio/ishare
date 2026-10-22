package releasenotes

import (
	"fmt"
	"strings"
	"testing"
)

const sample = `## [5.0.0](https://github.com/itoolio/ishare/compare/v4.2.6...v5.0.0) (2026-10-20)

### ⚠ BREAKING CHANGES

* the custom screencapture binary setting was removed

### Features

* **capture:** capture with ScreenCaptureKit and on-screen selectors ([8b4c984](https://github.com/itoolio/ishare/commit/8b4c984)), closes [#114](https://github.com/itoolio/ishare/issues/114) [#116](https://github.com/itoolio/ishare/issues/116)
* **upload:** async upload service with S3 support ([4a0b202](https://github.com/itoolio/ishare/commit/4a0b202))

### Bug Fixes

* **i18n:** correct German typos and capitalization ([7a1eef0](https://github.com/itoolio/ishare/commit/7a1eef0)), closes [#144](https://github.com/itoolio/ishare/issues/144)
`

func TestConvertProducesPlainText(t *testing.T) {
	got := Convert(sample)
	want := "Breaking Changes:\n• The custom screencapture binary setting was removed\n\nFeatures:\n• Capture with ScreenCaptureKit and on-screen selectors\n• Async upload service with S3 support\n\nBug Fixes:\n• Correct German typos and capitalization"
	if got != want {
		t.Fatalf("unexpected notes:\n%s", got)
	}
}

func TestConvertDropsTrailersDuplicatesAndUnknownSections(t *testing.T) {
	input := "### ⚠ BREAKING CHANGES\n\n* the menu changed\nCo-Authored-By: Someone <someone@example.com>\n* the menu changed\n\n### release\n\n* ishare 5.0\n\n### Features\n\n* **ui:** add <b>bold</b> option 🎉 (#146)\n* add bold option (#147)\n"
	got := Convert(input)
	want := "Breaking Changes:\n• The menu changed\n\nFeatures:\n• Add bold option"
	if got != want {
		t.Fatalf("unexpected notes:\n%s", got)
	}
}

func TestConvertTruncatesLongNotes(t *testing.T) {
	var builder strings.Builder
	builder.WriteString("### Features\n")
	for index := range 200 {
		fmt.Fprintf(&builder, "* feature number %d that is fairly long to describe here\n", index)
	}
	long := builder.String()
	got := Convert(long)
	if len([]rune(got)) > appStoreLimit {
		t.Fatalf("notes are %d characters long", len([]rune(got)))
	}
	if !strings.HasSuffix(got, "…") {
		t.Fatal("expected an ellipsis at the end")
	}
}

func TestRenderFallsBackWhenNothingIsUserFacing(t *testing.T) {
	if got := Render("## 5.0.1\n\n### Miscellaneous Chores\n\n* bump deps\n"); got != fallback {
		t.Fatalf("unexpected notes %q", got)
	}
	if got := Render(sample); got != Convert(sample) {
		t.Fatalf("unexpected notes %q", got)
	}
}
