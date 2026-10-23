package screenshots

import (
	"image"
	"image/png"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func writePNG(t *testing.T, width, height int) string {
	t.Helper()
	path := filepath.Join(t.TempDir(), "shot.png")
	file, err := os.Create(path)
	if err != nil {
		t.Fatal(err)
	}
	defer file.Close()
	if err := png.Encode(file, image.NewGray(image.Rect(0, 0, width, height))); err != nil {
		t.Fatal(err)
	}
	return path
}

func TestCheckPixelSizeAcceptsOnlyFullResolutionCaptures(t *testing.T) {
	if err := CheckPixelSize(writePNG(t, 2880, 1800)); err != nil {
		t.Fatal(err)
	}
	if err := CheckPixelSize(writePNG(t, 1024, 740)); err == nil || !strings.Contains(err.Error(), "1024x740") {
		t.Fatalf("unexpected error %v", err)
	}
}

func TestParseReady(t *testing.T) {
	cases := map[string]string{
		"ready display=5 points=1680x1050 pixels=3360x2100 main=1": "",
		"ready display=5 points=1680x1050 pixels=1680x1050 main=1": "at 2x",
		"ready display=5 points=1680x1050 pixels=3360x2100 main=0": "main display",
	}
	for line, expected := range cases {
		ok, err := ParseReady(line)
		if expected == "" && (!ok || err != nil) {
			t.Errorf("%q: ok=%v err=%v", line, ok, err)
		}
		if expected != "" && (err == nil || !strings.Contains(err.Error(), expected)) {
			t.Errorf("%q: expected an error about %q, got %v", line, expected, err)
		}
	}
	if ok, err := ParseReady("creating the display"); ok || err != nil {
		t.Fatalf("a progress line was treated as ready: %v %v", ok, err)
	}
}

func TestVirtualDisplayArgumentsCompileTheHelper(t *testing.T) {
	arguments := VirtualDisplayArguments("main.m", "out")
	if arguments[0] != "clang" || arguments[len(arguments)-1] != "out" || !strings.Contains(strings.Join(arguments, " "), "-framework CoreGraphics") {
		t.Fatalf("unexpected arguments %v", arguments)
	}
}
