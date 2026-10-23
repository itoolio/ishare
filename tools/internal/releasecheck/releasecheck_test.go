package releasecheck

import (
	"bytes"
	"fmt"
	"image"
	"image/color"
	"image/jpeg"
	"image/png"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/itoolio/ishare/tools/internal/repo"
)

const allowlistJSON = `{
  "ignoredEntitlements": ["com.apple.application-identifier"],
  "bundles": {
    "dev.example.app": {
      "com.apple.security.app-sandbox": "Required.",
      "com.apple.security.device.camera": "Webcam bubble."
    },
    "dev.example.app.widgets": {
      "com.apple.security.app-sandbox": "Required."
    }
  },
  "reviewNotes": [
    {"topic": "the camera", "entitlement": "com.apple.security.device.camera", "mentions": ["com.apple.security.device.camera"]},
    {"topic": "keychain groups", "entitlement": "keychain-access-groups", "mentions": ["keychain-access-groups"]},
    {"topic": "Input Monitoring", "mentions": ["Input Monitoring"]}
  ]
}`

func testAllowlist(t *testing.T) Allowlist {
	t.Helper()
	allowlist, err := ParseAllowlist([]byte(allowlistJSON))
	if err != nil {
		t.Fatal(err)
	}
	return allowlist
}

func TestTheCommittedAllowlistIsValid(t *testing.T) {
	allowlist, err := LoadAllowlist(repo.Path("fastlane", "entitlements-allowlist.json"))
	if err != nil {
		t.Fatal(err)
	}
	if _, ok := allowlist.Bundles["dev.adrian.ishare"]; !ok {
		t.Fatal("the allowlist does not cover the app")
	}
	notes, err := os.ReadFile(repo.Path("fastlane", "review_notes.txt"))
	if err != nil {
		t.Fatal(err)
	}
	present := map[string]bool{}
	for _, entitlements := range allowlist.Bundles {
		for key := range entitlements {
			present[key] = true
		}
	}
	if problems := CheckReviewNotes(string(notes), present, allowlist); len(problems) > 0 {
		t.Fatalf("the committed review notes miss topics: %v", problems)
	}
}

func TestAllowlistNeedsJustifications(t *testing.T) {
	if _, err := ParseAllowlist([]byte(`{"bundles": {"a": {"com.apple.security.device.camera": " "}}}`)); err == nil || !strings.Contains(err.Error(), "justification") {
		t.Fatalf("unexpected error %v", err)
	}
	if _, err := ParseAllowlist([]byte(`{"bundles": {}}`)); err == nil {
		t.Fatal("an empty allowlist was accepted")
	}
}

func TestCheckEntitlementsFlagsNewEntitlementsAndUnknownBundles(t *testing.T) {
	allowlist := testAllowlist(t)
	entitlements := map[string]any{
		"com.apple.security.app-sandbox":              true,
		"com.apple.security.device.camera":            true,
		"com.apple.application-identifier":            "TEAM.dev.example.app",
		"com.apple.security.device.usb":               false,
		"com.apple.security.temporary-exception.sbpl": []any{"(allow)"},
	}
	problems := CheckEntitlements("dev.example.app", entitlements, allowlist)
	if len(problems) != 1 || !strings.Contains(problems[0], "com.apple.security.temporary-exception.sbpl") {
		t.Fatalf("unexpected problems %v", problems)
	}
	if problems := CheckEntitlements("dev.example.other", entitlements, allowlist); len(problems) != 1 || !strings.Contains(problems[0], "not in the entitlements allowlist") {
		t.Fatalf("unexpected problems %v", problems)
	}
}

func TestCheckReviewNotesOnlyAsksForPresentEntitlements(t *testing.T) {
	allowlist := testAllowlist(t)
	present := map[string]bool{"com.apple.security.device.camera": true}
	problems := CheckReviewNotes("Input Monitoring is used for keystrokes.", present, allowlist)
	if len(problems) != 1 || !strings.Contains(problems[0], "the camera") {
		t.Fatalf("unexpected problems %v", problems)
	}
	if problems := CheckReviewNotes("Camera (com.apple.security.device.camera) and input monitoring.", present, allowlist); len(problems) != 0 {
		t.Fatalf("unexpected problems %v", problems)
	}
}

const otoolOutput = `/Applications/ishare.app/Contents/MacOS/ishare:
	/System/Library/Frameworks/ScreenCaptureKit.framework/Versions/A/ScreenCaptureKit (compatibility version 1.0.0, current version 1.0.0)
	/System/Library/Frameworks/AVFoundation.framework/Versions/A/AVFoundation (compatibility version 1.0.0, current version 2.0.0)
	@rpath/Sparkle.framework/Versions/B/Sparkle (compatibility version 1.6.0, current version 2.10.0)
	/System/Library/Frameworks/Contacts.framework/Versions/A/Contacts (compatibility version 1.0.0, current version 1.0.0, weak)
	/usr/lib/libSystem.B.dylib (compatibility version 1.0.0, current version 1351.0.0)
	/System/Library/Frameworks/AVFoundation.framework/Versions/A/AVFoundation (compatibility version 1.0.0, current version 2.0.0)
`

func TestParseLinkedFrameworks(t *testing.T) {
	got := strings.Join(ParseLinkedFrameworks(otoolOutput), ",")
	if got != "AVFoundation,Contacts,ScreenCaptureKit,Sparkle" {
		t.Fatalf("unexpected frameworks %q", got)
	}
}

func TestCheckUsageDescriptions(t *testing.T) {
	frameworks := ParseLinkedFrameworks(otoolOutput)
	entitlements := map[string]any{"com.apple.security.device.camera": true, "com.apple.security.device.audio-input": false}
	requirements := RequiredUsageDescriptions(frameworks, entitlements)
	info := map[string]any{
		"NSScreenCaptureUsageDescription": "Captures the screen",
		"NSCameraUsageDescription":        " ",
	}
	problems := CheckUsageDescriptions("dev.example.app", info, requirements)
	joined := strings.Join(problems, "\n")
	if len(problems) != 2 || !strings.Contains(joined, "NSContactsUsageDescription") || !strings.Contains(joined, "NSCameraUsageDescription") {
		t.Fatalf("unexpected problems %v", problems)
	}
	if strings.Contains(joined, "NSMicrophoneUsageDescription") {
		t.Fatal("a disabled entitlement required a usage description")
	}
}

func writeImage(t *testing.T, path string, width, height int, opaque bool) {
	t.Helper()
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		t.Fatal(err)
	}
	var buffer bytes.Buffer
	bounds := image.Rect(0, 0, width, height)
	var err error
	switch {
	case strings.HasSuffix(path, ".jpg"):
		err = jpeg.Encode(&buffer, image.NewGray(bounds), nil)
	case opaque:
		err = png.Encode(&buffer, image.NewGray(bounds))
	default:
		canvas := image.NewNRGBA(bounds)
		canvas.Set(0, 0, color.NRGBA{A: 10})
		err = png.Encode(&buffer, canvas)
	}
	if err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, buffer.Bytes(), 0o644); err != nil {
		t.Fatal(err)
	}
}

func TestCheckScreenshots(t *testing.T) {
	directory := t.TempDir()
	writeImage(t, filepath.Join(directory, "en-US", "01_menu.jpg"), ScreenshotWidth, ScreenshotHeight, true)
	writeImage(t, filepath.Join(directory, "en-US", "02_editor.png"), ScreenshotWidth, ScreenshotHeight, true)
	if problems := CheckScreenshots(directory); len(problems) != 0 {
		t.Fatalf("unexpected problems %v", problems)
	}
	writeImage(t, filepath.Join(directory, "de-DE", "01_menu.jpg"), 1440, 900, true)
	writeImage(t, filepath.Join(directory, "de-DE", "02_editor.png"), ScreenshotWidth, ScreenshotHeight, false)
	problems := CheckScreenshots(directory)
	joined := strings.Join(problems, "\n")
	if len(problems) != 2 || !strings.Contains(joined, "1440x900") || !strings.Contains(joined, "alpha channel") {
		t.Fatalf("unexpected problems %v", problems)
	}
	if problems := CheckScreenshots(t.TempDir()); len(problems) != 1 || !strings.Contains(problems[0], "no committed screenshots") {
		t.Fatalf("unexpected problems %v", problems)
	}
}

func TestCheckScreenshotsLimitsTheCountPerLocale(t *testing.T) {
	directory := t.TempDir()
	for index := range maximumScreenshots + 1 {
		writeImage(t, filepath.Join(directory, "en-US", fmt.Sprintf("%02d.jpg", index)), 16, 10, true)
	}
	if problems := CheckScreenshots(directory); !strings.Contains(strings.Join(problems, "\n"), "the App Store allows 10") {
		t.Fatalf("unexpected problems %v", problems)
	}
}

type fakeInspector struct {
	info         map[string]string
	entitlements map[string]string
	libraries    map[string]string
}

func (inspector fakeInspector) Entitlements(bundle string) ([]byte, error) {
	return []byte(inspector.entitlements[filepath.Base(bundle)]), nil
}

func (inspector fakeInspector) InfoPlist(bundle string) ([]byte, error) {
	return []byte(inspector.info[filepath.Base(bundle)]), nil
}

func (inspector fakeInspector) LinkedLibraries(binary string) (string, error) {
	return inspector.libraries[filepath.Base(binary)], nil
}

func plistDictionary(entries string) string {
	return `<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict>` + entries + `</dict></plist>`
}

func TestRunChecksAnArchive(t *testing.T) {
	root := t.TempDir()
	archive := filepath.Join(root, "ishare.xcarchive")
	app := filepath.Join(archive, "Products", "Applications", "ishare.app")
	for _, directory := range []string{filepath.Join(app, "Contents", "MacOS"), filepath.Join(app, "Contents", "PlugIns", "widgets.appex", "Contents", "MacOS")} {
		if err := os.MkdirAll(directory, 0o755); err != nil {
			t.Fatal(err)
		}
	}
	allowlistPath := filepath.Join(root, "allowlist.json")
	reviewNotes := filepath.Join(root, "review_notes.txt")
	releaseNotes := filepath.Join(root, "release_notes.txt")
	screenshots := filepath.Join(root, "screenshots")
	writeImage(t, filepath.Join(screenshots, "en-US", "01.jpg"), ScreenshotWidth, ScreenshotHeight, true)
	files := map[string]string{
		allowlistPath: allowlistJSON,
		reviewNotes:   "The webcam uses com.apple.security.device.camera. Input Monitoring shows keystrokes.",
		releaseNotes:  "Features:\n• A widget",
	}
	for path, content := range files {
		if err := os.WriteFile(path, []byte(content), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	inspector := fakeInspector{
		info: map[string]string{
			"ishare.app":    plistDictionary(`<key>CFBundleIdentifier</key><string>dev.example.app</string><key>CFBundleExecutable</key><string>ishare</string><key>NSCameraUsageDescription</key><string>Webcam</string><key>NSScreenCaptureUsageDescription</key><string>Screen</string>`),
			"widgets.appex": plistDictionary(`<key>CFBundleIdentifier</key><string>dev.example.app.widgets</string><key>CFBundleExecutable</key><string>widgets</string>`),
		},
		entitlements: map[string]string{
			"ishare.app":    plistDictionary(`<key>com.apple.security.app-sandbox</key><true/><key>com.apple.security.device.camera</key><true/>`),
			"widgets.appex": plistDictionary(`<key>com.apple.security.app-sandbox</key><true/>`),
		},
		libraries: map[string]string{
			"ishare": "x:\n\t/System/Library/Frameworks/ScreenCaptureKit.framework/Versions/A/ScreenCaptureKit (compatibility version 1.0.0)\n",
		},
	}
	options := Options{App: archive, Allowlist: allowlistPath, ReviewNotes: reviewNotes, Screenshots: screenshots, ReleaseNotes: releaseNotes, Inspector: inspector}
	var output bytes.Buffer
	options.Output = &output
	if _, err := Run(options); err != nil {
		t.Fatalf("%v\n%s", err, output.String())
	}
	for _, name := range []string{"entitlements", "usage descriptions", "review notes", "screenshots", "release notes"} {
		if !strings.Contains(output.String(), "ok   "+name) {
			t.Errorf("%s did not pass:\n%s", name, output.String())
		}
	}

	inspector.entitlements["widgets.appex"] = plistDictionary(`<key>com.apple.security.app-sandbox</key><true/><key>com.apple.security.network.server</key><true/>`)
	options.Inspector = inspector
	output.Reset()
	if _, err := Run(options); err == nil || !strings.Contains(output.String(), "new entitlement com.apple.security.network.server") {
		t.Fatalf("a new entitlement was not reported:\n%s", output.String())
	}
}

func TestRunSkipsAppChecksWithoutAnApp(t *testing.T) {
	root := t.TempDir()
	allowlistPath := filepath.Join(root, "allowlist.json")
	reviewNotes := filepath.Join(root, "notes.txt")
	os.WriteFile(allowlistPath, []byte(allowlistJSON), 0o644)
	os.WriteFile(reviewNotes, []byte("com.apple.security.device.camera, keychain-access-groups, Input Monitoring"), 0o644)
	screenshots := filepath.Join(root, "screenshots")
	writeImage(t, filepath.Join(screenshots, "en-US", "01.jpg"), ScreenshotWidth, ScreenshotHeight, true)
	var output bytes.Buffer
	if _, err := Run(Options{Allowlist: allowlistPath, ReviewNotes: reviewNotes, Screenshots: screenshots, Output: &output}); err != nil {
		t.Fatalf("%v\n%s", err, output.String())
	}
	if !strings.Contains(output.String(), "SKIP entitlements") || !strings.Contains(output.String(), "SKIP release notes") {
		t.Fatalf("unexpected output:\n%s", output.String())
	}
}

func TestReviewNotesMustFitAppStoreConnect(t *testing.T) {
	notes := strings.Repeat("a", MaxReviewNotesLength+1)
	problems := CheckReviewNotes(notes, map[string]bool{}, Allowlist{})
	if len(problems) != 1 || !strings.Contains(problems[0], "at most 4000") {
		t.Fatalf("unexpected problems %v", problems)
	}
	if problems := CheckReviewNotes(strings.Repeat("ä", MaxReviewNotesLength), map[string]bool{}, Allowlist{}); len(problems) != 0 {
		t.Fatalf("notes of exactly the limit were rejected: %v", problems)
	}
}
