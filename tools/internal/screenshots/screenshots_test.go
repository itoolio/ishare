package screenshots

import (
	"path/filepath"
	"reflect"
	"slices"
	"testing"
)

func TestParseTargets(t *testing.T) {
	got, err := ParseTargets(nil)
	if err != nil || !reflect.DeepEqual(got, []Target{{Locale: "en-US", Language: "en"}}) {
		t.Fatalf("unexpected default targets %v, %v", got, err)
	}
	got, err = ParseTargets([]string{"de-DE", "zh-Hans:zh-Hans", "pt-BR:pt-BR"})
	want := []Target{{"de-DE", "de"}, {"zh-Hans", "zh-Hans"}, {"pt-BR", "pt-BR"}}
	if err != nil || !reflect.DeepEqual(got, want) {
		t.Fatalf("unexpected targets %v, %v", got, err)
	}
	for _, invalid := range []string{"", ":en", "en-US:", "../en"} {
		if _, err := ParseTargets([]string{invalid}); err == nil {
			t.Errorf("expected %q to be rejected", invalid)
		}
	}
}

func TestScreenshotName(t *testing.T) {
	cases := map[string]string{
		"01_menu_0_6A1F2C3D-1111-2222-3333-444455556666.png": "01_menu.png",
		"02_editor.png":      "02_editor.png",
		"03_uploaders":       "03_uploaders.png",
		"../../evil_0_x.png": "evil.png",
		"":                   "",
	}
	for suggested, want := range cases {
		if got := ScreenshotName(suggested); got != want {
			t.Errorf("ScreenshotName(%q) = %q, want %q", suggested, got, want)
		}
	}
}

func TestPlanCopies(t *testing.T) {
	manifest := []byte(`[
		{"testIdentifier": "ScreenshotTests/testCaptureAppStoreScreenshots()", "attachments": [
			{"exportedFileName": "B.png", "suggestedHumanReadableName": "02_editor_0_B.png"},
			{"exportedFileName": "A.png", "suggestedHumanReadableName": "01_menu_0_A.png"},
			{"exportedFileName": "", "suggestedHumanReadableName": "03_ignored_0_C.png"}
		]}
	]`)
	got, err := PlanCopies(manifest, "in", "out")
	if err != nil {
		t.Fatal(err)
	}
	want := []Copy{
		{Source: filepath.Join("in", "A.png"), Destination: filepath.Join("out", "01_menu.png")},
		{Source: filepath.Join("in", "B.png"), Destination: filepath.Join("out", "02_editor.png")},
	}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("got %v", got)
	}
}

func TestPlanCopiesFailsWithoutScreenshots(t *testing.T) {
	if _, err := PlanCopies([]byte(`[{"attachments": []}]`), "in", "out"); err == nil {
		t.Fatal("expected an error")
	}
	if _, err := PlanCopies([]byte(`not json`), "in", "out"); err == nil {
		t.Fatal("expected an error")
	}
}

func TestXcodebuildArgumentsOnlyRunScreenshotTestsUnsigned(t *testing.T) {
	test := TestArguments("dd", "result.xcresult")
	for _, required := range []string{"test-without-building", "-only-testing:ishareUITests/ScreenshotTests", "CODE_SIGN_IDENTITY=-", "Screenshots"} {
		if !slices.Contains(test, required) {
			t.Errorf("test arguments are missing %q", required)
		}
	}
	build := BuildArguments("dd")
	if build[0] != "build-for-testing" || !slices.Contains(build, "CODE_SIGN_STYLE=Manual") {
		t.Errorf("unexpected build arguments %v", build)
	}
}
