package releasecheck

import (
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strings"

	"github.com/itoolio/ishare/tools/internal/plist"
	"github.com/itoolio/ishare/tools/internal/releasenotes"
)

type Inspector interface {
	Entitlements(bundle string) ([]byte, error)
	InfoPlist(bundle string) ([]byte, error)
	LinkedLibraries(binary string) (string, error)
}

type Options struct {
	App          string
	Allowlist    string
	ReviewNotes  string
	Screenshots  string
	ReleaseNotes string
	Inspector    Inspector
	Output       io.Writer
}

type Result struct {
	Name     string
	Problems []string
	Skipped  string
}

type Bundle struct {
	Path         string
	Identifier   string
	Executables  []string
	Info         map[string]any
	Entitlements map[string]any
}

func Run(options Options) ([]Result, error) {
	allowlist, err := LoadAllowlist(options.Allowlist)
	if err != nil {
		return nil, err
	}
	var results []Result
	bundles, appResults := inspectApp(options, allowlist)
	results = append(results, appResults...)
	results = append(results, reviewNotesResult(options, allowlist, bundles))
	results = append(results, Result{Name: "screenshots", Problems: CheckScreenshots(options.Screenshots)})
	results = append(results, releaseNotesResult(options))
	report(options.Output, results)
	for _, result := range results {
		if len(result.Problems) > 0 {
			return results, fmt.Errorf("the release checklist failed")
		}
	}
	return results, nil
}

func inspectApp(options Options, allowlist Allowlist) ([]Bundle, []Result) {
	names := []string{"entitlements", "usage descriptions"}
	if options.App == "" {
		return nil, skipped(names, "no app was given, pass --app with the archived ishare.app or .xcarchive")
	}
	bundles, err := LoadBundles(options.App, options.Inspector)
	if err != nil {
		return nil, []Result{{Name: names[0], Problems: []string{err.Error()}}}
	}
	entitlements := Result{Name: names[0]}
	usage := Result{Name: names[1]}
	for _, bundle := range bundles {
		entitlements.Problems = append(entitlements.Problems, CheckEntitlements(bundle.Identifier, bundle.Entitlements, allowlist)...)
		frameworks, err := linkedFrameworks(bundle, options.Inspector)
		if err != nil {
			usage.Problems = append(usage.Problems, err.Error())
			continue
		}
		usage.Problems = append(usage.Problems, CheckUsageDescriptions(bundle.Identifier, bundle.Info, RequiredUsageDescriptions(frameworks, bundle.Entitlements))...)
	}
	return bundles, []Result{entitlements, usage}
}

func reviewNotesResult(options Options, allowlist Allowlist, bundles []Bundle) Result {
	notes, err := os.ReadFile(options.ReviewNotes)
	if err != nil {
		return Result{Name: "review notes", Problems: []string{err.Error()}}
	}
	present := map[string]bool{}
	if bundles == nil {
		for _, entitlements := range allowlist.Bundles {
			for key := range entitlements {
				present[key] = true
			}
		}
	}
	for _, bundle := range bundles {
		for key, value := range bundle.Entitlements {
			if enabled, isBool := value.(bool); !isBool || enabled {
				present[key] = true
			}
		}
	}
	return Result{Name: "review notes", Problems: CheckReviewNotes(string(notes), present, allowlist)}
}

func releaseNotesResult(options Options) Result {
	if options.ReleaseNotes == "" {
		return Result{Name: "release notes", Skipped: "no release notes file was given, pass --release-notes"}
	}
	notes, err := os.ReadFile(options.ReleaseNotes)
	if err != nil {
		return Result{Name: "release notes", Problems: []string{err.Error()}}
	}
	return Result{Name: "release notes", Problems: releasenotes.Problems(string(notes))}
}

func skipped(names []string, reason string) []Result {
	results := make([]Result, len(names))
	for index, name := range names {
		results[index] = Result{Name: name, Skipped: reason}
	}
	return results
}

func report(output io.Writer, results []Result) {
	if output == nil {
		return
	}
	for _, result := range results {
		switch {
		case result.Skipped != "":
			fmt.Fprintf(output, "SKIP %s: %s\n", result.Name, result.Skipped)
		case len(result.Problems) == 0:
			fmt.Fprintf(output, "ok   %s\n", result.Name)
		default:
			fmt.Fprintf(output, "FAIL %s\n", result.Name)
			for _, problem := range result.Problems {
				fmt.Fprintf(output, "     - %s\n", problem)
			}
		}
	}
}

func ResolveApp(path string) (string, error) {
	if !strings.HasSuffix(strings.TrimSuffix(path, "/"), ".xcarchive") {
		return path, nil
	}
	matches, err := filepath.Glob(filepath.Join(path, "Products", "Applications", "*.app"))
	if err != nil {
		return "", err
	}
	if len(matches) != 1 {
		return "", fmt.Errorf("%s contains %d apps, expected one", path, len(matches))
	}
	return matches[0], nil
}

func BundlePaths(app string) ([]string, error) {
	paths := []string{app}
	for _, folder := range []string{"PlugIns", "Extensions"} {
		matches, err := filepath.Glob(filepath.Join(app, "Contents", folder, "*.appex"))
		if err != nil {
			return nil, err
		}
		sort.Strings(matches)
		paths = append(paths, matches...)
	}
	return paths, nil
}

func LoadBundles(path string, inspector Inspector) ([]Bundle, error) {
	app, err := ResolveApp(path)
	if err != nil {
		return nil, err
	}
	if _, err := os.Stat(app); err != nil {
		return nil, err
	}
	paths, err := BundlePaths(app)
	if err != nil {
		return nil, err
	}
	bundles := make([]Bundle, 0, len(paths))
	for _, bundlePath := range paths {
		bundle, err := loadBundle(bundlePath, inspector)
		if err != nil {
			return nil, fmt.Errorf("%s: %w", filepath.Base(bundlePath), err)
		}
		bundles = append(bundles, bundle)
	}
	return bundles, nil
}

func loadBundle(path string, inspector Inspector) (Bundle, error) {
	infoData, err := inspector.InfoPlist(path)
	if err != nil {
		return Bundle{}, err
	}
	info, err := plist.ParseDictionary(infoData)
	if err != nil {
		return Bundle{}, fmt.Errorf("Info.plist: %w", err)
	}
	identifier, _ := info["CFBundleIdentifier"].(string)
	executable, _ := info["CFBundleExecutable"].(string)
	if identifier == "" || executable == "" {
		return Bundle{}, fmt.Errorf("the Info.plist has no CFBundleIdentifier or CFBundleExecutable")
	}
	entitlementData, err := inspector.Entitlements(path)
	if err != nil {
		return Bundle{}, err
	}
	entitlements := map[string]any{}
	if strings.TrimSpace(string(entitlementData)) != "" {
		if entitlements, err = plist.ParseDictionary(entitlementData); err != nil {
			return Bundle{}, fmt.Errorf("entitlements: %w", err)
		}
	}
	executables := []string{filepath.Join(path, "Contents", "MacOS", executable)}
	debug := executables[0] + ".debug.dylib"
	if _, err := os.Stat(debug); err == nil {
		executables = append(executables, debug)
	}
	return Bundle{Path: path, Identifier: identifier, Executables: executables, Info: info, Entitlements: entitlements}, nil
}

func linkedFrameworks(bundle Bundle, inspector Inspector) ([]string, error) {
	var output strings.Builder
	for _, executable := range bundle.Executables {
		libraries, err := inspector.LinkedLibraries(executable)
		if err != nil {
			return nil, fmt.Errorf("%s: %w", bundle.Identifier, err)
		}
		output.WriteString(libraries)
		output.WriteString("\n")
	}
	return ParseLinkedFrameworks(output.String()), nil
}

type SystemInspector struct{}

func (SystemInspector) Entitlements(bundle string) ([]byte, error) {
	return command("codesign", "--display", "--entitlements", "-", "--xml", bundle)
}

func (SystemInspector) InfoPlist(bundle string) ([]byte, error) {
	return command("plutil", "-convert", "xml1", "-o", "-", filepath.Join(bundle, "Contents", "Info.plist"))
}

func (SystemInspector) LinkedLibraries(binary string) (string, error) {
	output, err := command("otool", "-L", binary)
	return string(output), err
}

func command(name string, arguments ...string) ([]byte, error) {
	output, err := exec.Command(name, arguments...).Output()
	if err != nil {
		if exit, ok := err.(*exec.ExitError); ok {
			return nil, fmt.Errorf("%s failed: %s", name, strings.TrimSpace(string(exit.Stderr)))
		}
		return nil, fmt.Errorf("%s failed: %w", name, err)
	}
	return output, nil
}
