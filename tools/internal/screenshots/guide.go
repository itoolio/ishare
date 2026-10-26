package screenshots

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strings"
)

const (
	guideTestID       = "ishareUITests/GuideClipTests"
	MaximumClipBytes  = 6 << 20
	MaximumPosterSize = 1 << 20
)

var GuideScenes = []string{"capture", "editor", "region", "shelf"}

type GuideOptions struct {
	Root   string
	Scenes []string
	Output io.Writer
	CI     bool
}

func ParseGuideScenes(arguments []string) ([]string, error) {
	if len(arguments) == 0 || (len(arguments) == 1 && arguments[0] == "all") {
		return append([]string{}, GuideScenes...), nil
	}
	known := map[string]bool{}
	for _, scene := range GuideScenes {
		known[scene] = true
	}
	seen := map[string]bool{}
	var scenes []string
	for _, argument := range arguments {
		for _, scene := range strings.Split(argument, ",") {
			scene = strings.TrimSpace(scene)
			if scene == "" || seen[scene] {
				continue
			}
			if !known[scene] {
				return nil, fmt.Errorf("%q is not a guide scene, use %s", scene, strings.Join(GuideScenes, ", "))
			}
			seen[scene] = true
			scenes = append(scenes, scene)
		}
	}
	if len(scenes) == 0 {
		return nil, fmt.Errorf("no guide scenes requested")
	}
	return scenes, nil
}

func GuideTestArguments(derivedData, result string) []string {
	return append([]string{
		"test-without-building",
		"-project", "ishare.xcodeproj",
		"-scheme", scheme,
		"-destination", "platform=macOS,arch=arm64",
		"-derivedDataPath", derivedData,
		"-resultBundlePath", result,
		"-only-testing:" + guideTestID,
		"-test-timeouts-enabled", "YES",
		"-maximum-test-execution-time-allowance", "2400",
	}, unsignedBuild...)
}

func GuideClipName(suggested, exported string) string {
	stem := strings.TrimSuffix(ScreenshotName(suggested), ".png")
	if !strings.HasPrefix(stem, "guide-") {
		return ""
	}
	scene := strings.TrimPrefix(stem, "guide-")
	if poster, ok := strings.CutSuffix(scene, "-poster"); ok {
		if !isGuideScene(poster) {
			return ""
		}
		return poster + ".jpg"
	}
	extension := strings.ToLower(filepath.Ext(exported))
	if !isGuideScene(scene) || (extension != ".mp4" && extension != ".m4v") {
		return ""
	}
	return scene + ".mp4"
}

func isGuideScene(name string) bool {
	for _, scene := range GuideScenes {
		if scene == name {
			return true
		}
	}
	return false
}

func PlanGuideCopies(manifest []byte, source, destination string) ([]Copy, error) {
	var tests []struct {
		Attachments []struct {
			SuggestedHumanReadableName string `json:"suggestedHumanReadableName"`
			ExportedFileName           string `json:"exportedFileName"`
		} `json:"attachments"`
	}
	if err := json.Unmarshal(manifest, &tests); err != nil {
		return nil, fmt.Errorf("couldn't read the attachment manifest: %w", err)
	}
	var copies []Copy
	for _, test := range tests {
		for _, attachment := range test.Attachments {
			name := GuideClipName(attachment.SuggestedHumanReadableName, attachment.ExportedFileName)
			if name == "" || attachment.ExportedFileName == "" {
				continue
			}
			copies = append(copies, Copy{
				Source:      filepath.Join(source, filepath.Base(attachment.ExportedFileName)),
				Destination: filepath.Join(destination, name),
			})
		}
	}
	if len(copies) == 0 {
		return nil, fmt.Errorf("no guide clips were exported")
	}
	sort.SliceStable(copies, func(left, right int) bool { return copies[left].Destination < copies[right].Destination })
	return copies, nil
}

func MissingGuideFiles(copies []Copy, scenes []string) []string {
	present := map[string]bool{}
	for _, copy := range copies {
		present[filepath.Base(copy.Destination)] = true
	}
	var missing []string
	for _, scene := range scenes {
		for _, name := range []string{scene + ".mp4", scene + ".jpg"} {
			if !present[name] {
				missing = append(missing, name)
			}
		}
	}
	return missing
}

func CheckClip(path string) error {
	data, err := os.ReadFile(path)
	if err != nil {
		return err
	}
	name := filepath.Base(path)
	switch filepath.Ext(path) {
	case ".mp4":
		if len(data) < 1024 || !bytes.Equal(data[4:8], []byte("ftyp")) {
			return fmt.Errorf("%s is not an MP4 file", name)
		}
		if len(data) > MaximumClipBytes {
			return fmt.Errorf("%s is %d bytes, more than the %d byte budget for a guide clip", name, len(data), MaximumClipBytes)
		}
	case ".jpg":
		if len(data) < 3 || data[0] != 0xFF || data[1] != 0xD8 {
			return fmt.Errorf("%s is not a JPEG file", name)
		}
		if len(data) > MaximumPosterSize {
			return fmt.Errorf("%s is %d bytes, more than the %d byte budget for a poster", name, len(data), MaximumPosterSize)
		}
	default:
		return fmt.Errorf("%s is not a guide clip or poster", name)
	}
	return nil
}

func RunGuide(options GuideOptions) error {
	work := filepath.Join(options.Root, "build", "guide")
	derivedData := filepath.Join(work, "DerivedData")
	output := filepath.Join(options.Root, "website", "public", "guide")
	attachments := filepath.Join(work, "attachments")
	result := filepath.Join(work, "Guide.xcresult")
	if err := os.RemoveAll(work); err != nil {
		return err
	}
	base := Options{Root: options.Root, Output: options.Output, CI: options.CI}
	if _, err := exec.LookPath("xcodegen"); err == nil {
		if err := run(base, nil, "xcodegen", "generate", "--quiet"); err != nil {
			return err
		}
	}
	if err := xcodebuild(base, nil, BuildArguments(derivedData)); err != nil {
		return err
	}
	if options.CI {
		stop, err := startVirtualDisplay(base, work)
		if err != nil {
			return err
		}
		defer stop()
	}
	for _, directory := range []string{attachments, output} {
		if err := os.MkdirAll(directory, 0o755); err != nil {
			return err
		}
	}
	environment := []string{"TEST_RUNNER_ISHARE_GUIDE_SCENES=" + strings.Join(options.Scenes, ",")}
	if err := xcodebuild(base, environment, GuideTestArguments(derivedData, result)); err != nil {
		return err
	}
	if err := run(base, nil, "xcrun", "xcresulttool", "export", "attachments", "--path", result, "--output-path", attachments); err != nil {
		return err
	}
	manifest, err := os.ReadFile(filepath.Join(attachments, "manifest.json"))
	if err != nil {
		return err
	}
	copies, err := PlanGuideCopies(manifest, attachments, output)
	if err != nil {
		return err
	}
	if missing := MissingGuideFiles(copies, options.Scenes); len(missing) > 0 {
		return fmt.Errorf("the guide run did not produce %s", strings.Join(missing, ", "))
	}
	for _, copy := range copies {
		if err := CheckClip(copy.Source); err != nil {
			return err
		}
		if err := copyFile(copy.Source, copy.Destination); err != nil {
			return err
		}
	}
	fmt.Fprintf(options.Output, "Exported %d guide files to %s\n", len(copies), output)
	return nil
}
