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

func TestConvertMergesSeveralReleasesNewestFirst(t *testing.T) {
	newer := "## [5.2.0](https://example.com) (2026-11-01)\n\n### Bug Fixes\n\n* **menu:** fix the toast ([1234567](https://example.com))\n\n### Features\n\n* **widgets:** add a Recent Uploads widget ([abcdef1](https://example.com))\n"
	older := "## [5.1.1](https://example.com) (2026-10-25)\n\n### Bug Fixes\n\n* **menu:** fix the toast ([7654321](https://example.com))\n* **editor:** keep the crop ([1111111](https://example.com))\n"
	got := Convert(newer + "\n" + older)
	want := "Features:\n• Add a Recent Uploads widget\n\nBug Fixes:\n• Fix the toast\n• Keep the crop"
	if got != want {
		t.Fatalf("unexpected notes:\n%s", got)
	}
}

func TestRenderedNotesHaveNoProblems(t *testing.T) {
	if problems := Problems(Render(sample)); len(problems) > 0 {
		t.Fatalf("unexpected problems %v", problems)
	}
}

func TestProblemsFlagMarkupSymbolsLengthAndEmptyNotes(t *testing.T) {
	cases := map[string]string{
		"## Features\n• Something":           "Markdown markup",
		"• Add **bold** text":                "Markdown markup",
		"• See [docs](https://example.com)":  "Markdown markup",
		"• Party 🎉":                          "symbols",
		"   ":                                "empty",
		strings.Repeat("a", appStoreLimit+1): "characters long",
	}
	for notes, expected := range cases {
		problems := Problems(notes)
		if len(problems) == 0 || !strings.Contains(strings.Join(problems, "\n"), expected) {
			t.Errorf("%q: expected a problem mentioning %q, got %v", notes, expected, problems)
		}
	}
}

func TestRenderFallsBackWhenNothingIsUserFacing(t *testing.T) {
	if got := Render("## 5.0.1\n\n### Miscellaneous Chores\n\n* bump deps\n"); got != Fallback {
		t.Fatalf("unexpected notes %q", got)
	}
	if got := Render(sample); got != Convert(sample) {
		t.Fatalf("unexpected notes %q", got)
	}
}
