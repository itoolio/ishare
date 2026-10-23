package screenshots

import (
	"bufio"
	"encoding/json"
	"fmt"
	"image"
	_ "image/jpeg"
	_ "image/png"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
	"time"

	"github.com/itoolio/ishare/tools/internal/locales"
)

const (
	scheme      = "Screenshots"
	testID      = "ishareUITests/ScreenshotTests"
	pixelHeight = "1800"
	pixelWidth  = "2880"
)

var unsignedBuild = []string{"CODE_SIGN_IDENTITY=-", "CODE_SIGN_STYLE=Manual", "DEVELOPMENT_TEAM=", "PROVISIONING_PROFILE_SPECIFIER="}

type Target struct {
	Locale   string
	Language string
}

type Copy struct {
	Source      string
	Destination string
}

type Options struct {
	Root    string
	Targets []Target
	Output  io.Writer
	CI      bool
}

func ParseTargets(arguments []string) ([]Target, error) {
	if len(arguments) == 0 {
		return []Target{{Locale: "en-US", Language: "en"}}, nil
	}
	if len(arguments) == 1 && arguments[0] == "all" {
		return AllTargets(), nil
	}
	targets := make([]Target, 0, len(arguments))
	for _, argument := range arguments {
		locale, language, explicit := strings.Cut(argument, ":")
		if known, ok := locales.ByAppStore(locale); ok && !explicit {
			language = known.Catalog
		} else if !explicit {
			language, _, _ = strings.Cut(locale, "-")
		}
		if locale == "" || language == "" || strings.ContainsAny(locale, `/\`) {
			return nil, fmt.Errorf("%q is not a locale, use <locale> or <locale>:<language> such as en-US:en", argument)
		}
		targets = append(targets, Target{Locale: locale, Language: language})
	}
	return targets, nil
}

func AllTargets() []Target {
	targets := make([]Target, len(locales.All))
	for index, locale := range locales.All {
		targets[index] = Target{Locale: locale.AppStore, Language: locale.Catalog}
	}
	return targets
}

func ScreenshotName(suggested string) string {
	stem, _, _ := strings.Cut(suggested, "_0_")
	stem = filepath.Base(stem)
	if dot := strings.LastIndex(stem, "."); dot >= 0 {
		stem = stem[:dot]
	}
	if stem == "" || stem == string(filepath.Separator) {
		return ""
	}
	return stem + ".png"
}

func PlanCopies(manifest []byte, source, destination string) ([]Copy, error) {
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
			name := ScreenshotName(attachment.SuggestedHumanReadableName)
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
		return nil, fmt.Errorf("no screenshots were exported")
	}
	sort.SliceStable(copies, func(left, right int) bool { return copies[left].Destination < copies[right].Destination })
	return copies, nil
}

func TestArguments(derivedData, result string) []string {
	return append([]string{
		"test-without-building",
		"-project", "ishare.xcodeproj",
		"-scheme", scheme,
		"-destination", "platform=macOS",
		"-derivedDataPath", derivedData,
		"-resultBundlePath", result,
		"-only-testing:" + testID,
		"-test-timeouts-enabled", "YES",
		"-maximum-test-execution-time-allowance", "600",
	}, unsignedBuild...)
}

func BuildArguments(derivedData string) []string {
	return append([]string{
		"build-for-testing",
		"-project", "ishare.xcodeproj",
		"-scheme", scheme,
		"-destination", "platform=macOS",
		"-derivedDataPath", derivedData,
	}, unsignedBuild...)
}

func Run(options Options) error {
	work := filepath.Join(options.Root, "build", "screenshots")
	derivedData := filepath.Join(work, "DerivedData")
	if err := os.RemoveAll(work); err != nil {
		return err
	}
	if _, err := exec.LookPath("xcodegen"); err == nil {
		if err := run(options, nil, "xcodegen", "generate", "--quiet"); err != nil {
			return err
		}
	}
	if err := xcodebuild(options, nil, BuildArguments(derivedData)); err != nil {
		return err
	}
	if options.CI {
		stop, err := startVirtualDisplay(options, work)
		if err != nil {
			return err
		}
		defer stop()
	}
	for _, target := range options.Targets {
		if err := capture(options, work, derivedData, target); err != nil {
			return fmt.Errorf("%s: %w", target.Locale, err)
		}
	}
	return nil
}

func capture(options Options, work, derivedData string, target Target) error {
	output := filepath.Join(options.Root, "fastlane", "screenshots", target.Locale)
	attachments := filepath.Join(work, "attachments", target.Locale)
	result := filepath.Join(work, "Screenshots-"+target.Locale+".xcresult")
	for _, directory := range []string{output, attachments} {
		if err := os.RemoveAll(directory); err != nil {
			return err
		}
		if err := os.MkdirAll(directory, 0o755); err != nil {
			return err
		}
	}
	environment := []string{"TEST_RUNNER_ISHARE_LANGUAGE=" + target.Language}
	if err := xcodebuild(options, environment, TestArguments(derivedData, result)); err != nil {
		return err
	}
	if err := run(options, nil, "xcrun", "xcresulttool", "export", "attachments", "--path", result, "--output-path", attachments); err != nil {
		return err
	}
	manifest, err := os.ReadFile(filepath.Join(attachments, "manifest.json"))
	if err != nil {
		return err
	}
	copies, err := PlanCopies(manifest, attachments, output)
	if err != nil {
		return err
	}
	for _, copy := range copies {
		if options.CI {
			if err := CheckPixelSize(copy.Source); err != nil {
				return err
			}
		}
		if err := copyFile(copy.Source, copy.Destination); err != nil {
			return err
		}
		if err := runTo(io.Discard, options, nil, "sips", "-z", pixelHeight, pixelWidth, copy.Destination); err != nil {
			return err
		}
		jpeg := JPEGPath(copy.Destination)
		if err := runTo(io.Discard, options, nil, "sips", "-s", "format", "jpeg", "-s", "formatOptions", jpegQuality, copy.Destination, "--out", jpeg); err != nil {
			return err
		}
		if err := os.Remove(copy.Destination); err != nil {
			return err
		}
	}
	fmt.Fprintf(options.Output, "Exported %d screenshots to %s\n", len(copies), output)
	return nil
}

const jpegQuality = "92"

func JPEGPath(png string) string {
	return strings.TrimSuffix(png, filepath.Ext(png)) + ".jpg"
}

func copyFile(source, destination string) error {
	data, err := os.ReadFile(source)
	if err != nil {
		return err
	}
	return os.WriteFile(destination, data, 0o644)
}

func run(options Options, environment []string, name string, arguments ...string) error {
	return runTo(options.Output, options, environment, name, arguments...)
}

func runTo(stdout io.Writer, options Options, environment []string, name string, arguments ...string) error {
	command := exec.Command(name, arguments...)
	command.Dir = options.Root
	command.Env = append(os.Environ(), environment...)
	command.Stdout = stdout
	command.Stderr = os.Stderr
	if err := command.Run(); err != nil {
		return fmt.Errorf("%s failed: %w", name, err)
	}
	return nil
}

func xcodebuild(options Options, environment []string, arguments []string) error {
	beautifier, err := exec.LookPath("xcbeautify")
	if err != nil {
		return run(options, environment, "xcodebuild", arguments...)
	}
	build := exec.Command("xcodebuild", arguments...)
	build.Dir = options.Root
	build.Env = append(os.Environ(), environment...)
	build.Stderr = os.Stderr
	pretty := exec.Command(beautifier)
	pretty.Stdout = options.Output
	pretty.Stderr = os.Stderr
	pipe, err := build.StdoutPipe()
	if err != nil {
		return err
	}
	pretty.Stdin = pipe
	if err := pretty.Start(); err != nil {
		return err
	}
	buildErr := build.Run()
	prettyErr := pretty.Wait()
	if buildErr != nil {
		return fmt.Errorf("xcodebuild %s failed: %w", arguments[0], buildErr)
	}
	return prettyErr
}

func CheckPixelSize(path string) error {
	file, err := os.Open(path)
	if err != nil {
		return err
	}
	defer file.Close()
	config, _, err := image.DecodeConfig(file)
	if err != nil {
		return fmt.Errorf("%s: %w", filepath.Base(path), err)
	}
	width, _ := strconv.Atoi(pixelWidth)
	height, _ := strconv.Atoi(pixelHeight)
	if config.Width != width || config.Height != height {
		return fmt.Errorf("%s is %dx%d instead of %dx%d; the window was not captured on a HiDPI display large enough for the 1440x900 point scene", filepath.Base(path), config.Width, config.Height, width, height)
	}
	return nil
}

func VirtualDisplayArguments(source, binary string) []string {
	return []string{"clang", "-fobjc-arc", "-framework", "Foundation", "-framework", "CoreGraphics", source, "-o", binary}
}

func ParseReady(line string) (bool, error) {
	if strings.HasPrefix(line, "ready ") {
		if !strings.Contains(line, "points=1680x1050") || !strings.Contains(line, "pixels=3360x2100") {
			return false, fmt.Errorf("the virtual display is not 1680x1050 points at 2x: %s", line)
		}
		if !strings.Contains(line, "main=1") {
			return false, fmt.Errorf("the virtual display did not become the main display: %s", line)
		}
		return true, nil
	}
	return false, nil
}

func startVirtualDisplay(options Options, work string) (func(), error) {
	binary := filepath.Join(work, "virtual-display")
	source := filepath.Join(options.Root, "tools", "virtualdisplay", "main.m")
	if err := run(options, nil, "xcrun", VirtualDisplayArguments(source, binary)...); err != nil {
		return nil, err
	}
	helper := exec.Command(binary, "--width", "1680", "--height", "1050", "--scale", "2")
	helper.Stderr = os.Stderr
	stdout, err := helper.StdoutPipe()
	if err != nil {
		return nil, err
	}
	if err := helper.Start(); err != nil {
		return nil, err
	}
	stop := func() {
		_ = helper.Process.Signal(os.Interrupt)
		_ = helper.Wait()
	}
	ready := make(chan error, 1)
	go func() {
		scanner := bufio.NewScanner(stdout)
		for scanner.Scan() {
			fmt.Fprintln(options.Output, scanner.Text())
			if ok, err := ParseReady(scanner.Text()); ok || err != nil {
				ready <- err
				return
			}
		}
		ready <- fmt.Errorf("the virtual display helper exited before it was ready")
	}()
	select {
	case err := <-ready:
		if err != nil {
			stop()
			return nil, err
		}
	case <-time.After(60 * time.Second):
		stop()
		return nil, fmt.Errorf("timed out waiting for the virtual display")
	}
	time.Sleep(2 * time.Second)
	return stop, nil
}
