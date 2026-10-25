package screenshots

import (
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"testing"
)

func TestParseGuideScenes(t *testing.T) {
	all, err := ParseGuideScenes(nil)
	if err != nil || !reflect.DeepEqual(all, GuideScenes) {
		t.Fatalf("got %v, %v", all, err)
	}
	if scenes, _ := ParseGuideScenes([]string{"all"}); !reflect.DeepEqual(scenes, GuideScenes) {
		t.Fatalf("all gave %v", scenes)
	}
	scenes, err := ParseGuideScenes([]string{"shelf,editor", "shelf"})
	if err != nil || !reflect.DeepEqual(scenes, []string{"shelf", "editor"}) {
		t.Fatalf("got %v, %v", scenes, err)
	}
	if _, err := ParseGuideScenes([]string{"nope"}); err == nil || !strings.Contains(err.Error(), "capture") {
		t.Fatalf("unexpected error %v", err)
	}
	if _, err := ParseGuideScenes([]string{","}); err == nil {
		t.Fatal("accepted an empty scene list")
	}
}

func TestGuideClipName(t *testing.T) {
	cases := map[[2]string]string{
		{"guide-capture_0_8A1B.mp4", "guide-capture_0_8A1B.mp4"}:             "capture.mp4",
		{"guide-shelf-poster_0_77.jpeg", "guide-shelf-poster_0_77.jpeg"}:     "shelf.jpg",
		{"guide-editor_0_1.mov", "guide-editor_0_1.mov"}:                     "",
		{"guide-unknown_0_1.mp4", "guide-unknown_0_1.mp4"}:                   "",
		{"guide-unknown-poster_0_1.jpeg", "guide-unknown-poster_0_1.jpeg"}:   "",
		{"01_menu_0_ABC.png", "01_menu_0_ABC.png"}:                           "",
		{"guide-../../etc/passwd_0_1.mp4", "guide-../../etc/passwd_0_1.mp4"}: "",
		{"", "x.mp4"}: "",
	}
	for input, expected := range cases {
		if name := GuideClipName(input[0], input[1]); name != expected {
			t.Errorf("%v: got %q, want %q", input, name, expected)
		}
	}
}

func TestPlanGuideCopiesAndMissingFiles(t *testing.T) {
	manifest := []byte(`[{"attachments": [
		{"suggestedHumanReadableName": "guide-region_0_A.mp4", "exportedFileName": "guide-region_0_A.mp4"},
		{"suggestedHumanReadableName": "guide-region-poster_0_B.jpeg", "exportedFileName": "guide-region-poster_0_B.jpeg"},
		{"suggestedHumanReadableName": "Screenshot_0_C.png", "exportedFileName": "Screenshot_0_C.png"}
	]}]`)
	copies, err := PlanGuideCopies(manifest, "/src", "/dst")
	if err != nil {
		t.Fatal(err)
	}
	expected := []Copy{{Source: "/src/guide-region-poster_0_B.jpeg", Destination: "/dst/region.jpg"}, {Source: "/src/guide-region_0_A.mp4", Destination: "/dst/region.mp4"}}
	if !reflect.DeepEqual(copies, expected) {
		t.Fatalf("got %v", copies)
	}
	if missing := MissingGuideFiles(copies, []string{"region", "shelf"}); !reflect.DeepEqual(missing, []string{"shelf.mp4", "shelf.jpg"}) {
		t.Fatalf("missing %v", missing)
	}
	if _, err := PlanGuideCopies([]byte(`[]`), "/src", "/dst"); err == nil {
		t.Fatal("accepted a run without clips")
	}
	if _, err := PlanGuideCopies([]byte(`{`), "/src", "/dst"); err == nil {
		t.Fatal("accepted a malformed manifest")
	}
}

func TestCheckClip(t *testing.T) {
	directory := t.TempDir()
	write := func(name string, data []byte) string {
		path := filepath.Join(directory, name)
		if err := os.WriteFile(path, data, 0o644); err != nil {
			t.Fatal(err)
		}
		return path
	}
	mp4 := append([]byte{0, 0, 0, 32, 'f', 't', 'y', 'p', 'i', 's', 'o', 'm'}, make([]byte, 2048)...)
	if err := CheckClip(write("ok.mp4", mp4)); err != nil {
		t.Fatal(err)
	}
	if CheckClip(write("bad.mp4", make([]byte, 4096))) == nil {
		t.Fatal("accepted a file without an ftyp box")
	}
	if CheckClip(write("huge.mp4", append(mp4, make([]byte, MaximumClipBytes)...))) == nil {
		t.Fatal("accepted an oversized clip")
	}
	if err := CheckClip(write("ok.jpg", []byte{0xFF, 0xD8, 0xFF, 0xE0})); err != nil {
		t.Fatal(err)
	}
	if CheckClip(write("bad.jpg", []byte("PNG"))) == nil {
		t.Fatal("accepted a poster that is not a JPEG")
	}
	if CheckClip(write("notes.txt", []byte("x"))) == nil {
		t.Fatal("accepted an unknown file type")
	}
}

func TestGuideTestArgumentsOnlyRunTheGuideTests(t *testing.T) {
	arguments := strings.Join(GuideTestArguments("/dd", "/r.xcresult"), " ")
	if !strings.Contains(arguments, "-only-testing:ishareUITests/GuideClipTests") || strings.Contains(arguments, "ScreenshotTests") {
		t.Fatalf("unexpected arguments %s", arguments)
	}
	if !strings.Contains(arguments, "test-without-building") || !strings.Contains(arguments, "-scheme Screenshots") {
		t.Fatalf("unexpected arguments %s", arguments)
	}
}
