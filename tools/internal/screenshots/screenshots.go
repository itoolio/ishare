package screenshots

import (
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
}

func ParseTargets(arguments []string) ([]Target, error) {
	if len(arguments) == 0 {
		return []Target{{Locale: "en-US", Language: "en"}}, nil
	}
	targets := make([]Target, 0, len(arguments))
	for _, argument := range arguments {
		locale, language, explicit := strings.Cut(argument, ":")
		if !explicit {
			language, _, _ = strings.Cut(locale, "-")
		}
		if locale == "" || language == "" || strings.ContainsAny(locale, `/\`) {
			return nil, fmt.Errorf("%q is not a locale, use <locale> or <locale>:<language> such as en-US:en", argument)
		}
		targets = append(targets, Target{Locale: locale, Language: language})
	}
	return targets, nil
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
		if err := copyFile(copy.Source, copy.Destination); err != nil {
			return err
		}
		if err := runTo(io.Discard, options, nil, "sips", "-z", pixelHeight, pixelWidth, copy.Destination); err != nil {
			return err
		}
	}
	fmt.Fprintf(options.Output, "Exported %d screenshots to %s\n", len(copies), output)
	return nil
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
