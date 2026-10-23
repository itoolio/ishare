package main

import (
	"errors"
	"flag"
	"fmt"
	"io"
	"os"
	"sort"
	"strings"

	"github.com/itoolio/ishare/tools/internal/appcast"
	"github.com/itoolio/ishare/tools/internal/appstore"
	"github.com/itoolio/ishare/tools/internal/appstoreplan"
	"github.com/itoolio/ishare/tools/internal/buildlog"
	"github.com/itoolio/ishare/tools/internal/coverage"
	"github.com/itoolio/ishare/tools/internal/metadata"
	"github.com/itoolio/ishare/tools/internal/releasecheck"
	"github.com/itoolio/ishare/tools/internal/releasenotes"
	"github.com/itoolio/ishare/tools/internal/repo"
	"github.com/itoolio/ishare/tools/internal/screenshots"
	symbolication "github.com/itoolio/ishare/tools/internal/symbolicate"
	"github.com/itoolio/ishare/tools/internal/version"
	"github.com/itoolio/ishare/tools/internal/xcstrings"
)

type environment struct {
	stdin  io.Reader
	stdout io.Writer
}

type command struct {
	usage string
	run   func(environment, []string) error
}

var errUsage = errors.New("usage")

var commands = map[string]command{
	"set-version":        {"set-version <version>", setVersion},
	"release-notes":      {"release-notes [output-file] < release.md", releaseNotes},
	"register-bundle-id": {"register-bundle-id [identifier...]", registerBundleID},
	"merge-translations": {"merge-translations <base.xcstrings> <incoming.xcstrings> <output.xcstrings>", mergeTranslations},
	"screenshots":        {"screenshots [--ci] [all | locale[:language]...]", captureScreenshots},
	"metadata":           {"metadata [--check] [--metadata dir] [--catalog Metadata.xcstrings] [--release-notes en-US/release_notes.txt]", renderMetadata},
	"app-store-plan":     {"app-store-plan --report status.json --releases releases.json", appStorePlan},
	"appcast-hardware":   {"appcast-hardware <requirement> <appcast.xml>", appcastHardware},
	"build-warnings":     {"build-warnings [--ignore fragment]... <xcodebuild.log>...", buildWarnings},
	"coverage":           {"coverage [--root dir] [--min Area=percent]... [--output summary.md] [--summary-file path] <xccov.json>", coverageReport},
	"symbolicate":        {"symbolicate <crash.ips|crash> --dsyms <dSYMs.zip|dir> [--output file]", symbolicate},
	"release-check":      {"release-check [--app ishare.app|ishare.xcarchive] [--release-notes file] [--allowlist file] [--review-notes file] [--screenshots dir] [--metadata dir]", releaseCheck},
}

func main() {
	os.Exit(run(os.Args[1:], environment{stdin: os.Stdin, stdout: os.Stdout}, os.Stderr))
}

func run(arguments []string, env environment, stderr io.Writer) int {
	if len(arguments) == 0 {
		fmt.Fprint(stderr, usage())
		return 2
	}
	selected, ok := commands[arguments[0]]
	if !ok {
		fmt.Fprintf(stderr, "unknown command %q\n\n%s", arguments[0], usage())
		return 2
	}
	if err := selected.run(env, arguments[1:]); err != nil {
		if errors.Is(err, errUsage) {
			fmt.Fprintf(stderr, "usage: ishare-tools %s\n", selected.usage)
			return 2
		}
		fmt.Fprintln(stderr, err)
		return 1
	}
	return 0
}

func usage() string {
	names := make([]string, 0, len(commands))
	for name := range commands {
		names = append(names, name)
	}
	sort.Strings(names)
	var builder strings.Builder
	builder.WriteString("usage: ishare-tools <command> [arguments]\n\ncommands:\n")
	for _, name := range names {
		builder.WriteString("  " + commands[name].usage + "\n")
	}
	return builder.String()
}

func setVersion(env environment, arguments []string) error {
	if len(arguments) != 1 {
		return errUsage
	}
	build, err := version.Set(arguments[0])
	if err != nil {
		return err
	}
	fmt.Fprintf(env.stdout, "version %s (%s)\n", arguments[0], build)
	return nil
}

func releaseNotes(env environment, arguments []string) error {
	if len(arguments) > 1 {
		return errUsage
	}
	input, err := io.ReadAll(env.stdin)
	if err != nil {
		return err
	}
	notes := releasenotes.Render(string(input)) + "\n"
	if len(arguments) == 1 {
		return os.WriteFile(arguments[0], []byte(notes), 0o644)
	}
	_, err = io.WriteString(env.stdout, notes)
	return err
}

func registerBundleID(env environment, arguments []string) error {
	identifiers := arguments
	if len(identifiers) == 0 {
		identifiers = appstore.ParseIdentifiers(os.Getenv("BUNDLE_IDENTIFIERS"))
	}
	if len(identifiers) == 0 {
		return fmt.Errorf("pass bundle identifiers as arguments or set BUNDLE_IDENTIFIERS")
	}
	credentials, err := appstore.CredentialsFromEnvironment()
	if err != nil {
		return err
	}
	name := os.Getenv("BUNDLE_NAME")
	if name == "" {
		name = "ishare"
	}
	return appstore.RegisterBundleIDs(credentials, name, identifiers, env.stdout)
}

func mergeTranslations(env environment, arguments []string) error {
	if len(arguments) != 3 {
		return errUsage
	}
	base, err := os.ReadFile(arguments[0])
	if err != nil {
		return err
	}
	incoming, err := os.ReadFile(arguments[1])
	if err != nil {
		return err
	}
	merged, result, err := xcstrings.MergeFiles(base, incoming)
	if err != nil {
		return err
	}
	if err := os.WriteFile(arguments[2], merged, 0o644); err != nil {
		return err
	}
	_, err = io.WriteString(env.stdout, result.Summary())
	return err
}

func captureScreenshots(env environment, arguments []string) error {
	flags := flag.NewFlagSet("screenshots", flag.ContinueOnError)
	flags.SetOutput(io.Discard)
	ci := flags.Bool("ci", false, "")
	if err := flags.Parse(arguments); err != nil {
		return errUsage
	}
	targets, err := screenshots.ParseTargets(flags.Args())
	if err != nil {
		return err
	}
	return screenshots.Run(screenshots.Options{Root: repo.Root(), Targets: targets, Output: env.stdout, CI: *ci})
}

func releaseCheck(env environment, arguments []string) error {
	flags := flag.NewFlagSet("release-check", flag.ContinueOnError)
	flags.SetOutput(io.Discard)
	options := releasecheck.Options{Inspector: releasecheck.SystemInspector{}, Output: env.stdout}
	flags.StringVar(&options.App, "app", "", "")
	flags.StringVar(&options.ReleaseNotes, "release-notes", "", "")
	flags.StringVar(&options.Allowlist, "allowlist", repo.Path("fastlane", "entitlements-allowlist.json"), "")
	flags.StringVar(&options.ReviewNotes, "review-notes", repo.Path("fastlane", "review_notes.txt"), "")
	flags.StringVar(&options.Screenshots, "screenshots", repo.Path("fastlane", "screenshots"), "")
	flags.StringVar(&options.Metadata, "metadata", repo.Path("fastlane", "metadata"), "")
	if err := flags.Parse(arguments); err != nil || flags.NArg() > 0 {
		return errUsage
	}
	_, err := releasecheck.Run(options)
	return err
}

func appStorePlan(env environment, arguments []string) error {
	flags := flag.NewFlagSet("app-store-plan", flag.ContinueOnError)
	flags.SetOutput(io.Discard)
	reportPath := flags.String("report", "", "")
	releasesPath := flags.String("releases", "", "")
	if err := flags.Parse(arguments); err != nil || flags.NArg() > 0 || *reportPath == "" || *releasesPath == "" {
		return errUsage
	}
	reportData, err := os.ReadFile(*reportPath)
	if err != nil {
		return err
	}
	report, err := appstoreplan.ParseReport(reportData)
	if err != nil {
		return err
	}
	releaseData, err := os.ReadFile(*releasesPath)
	if err != nil {
		return err
	}
	releases, err := appstoreplan.ParseReleases(releaseData)
	if err != nil {
		return err
	}
	_, err = io.WriteString(env.stdout, appstoreplan.Decide(report, releases).Outputs())
	return err
}

func renderMetadata(env environment, arguments []string) error {
	flags := flag.NewFlagSet("metadata", flag.ContinueOnError)
	flags.SetOutput(io.Discard)
	options := metadata.Options{Output: env.stdout}
	flags.BoolVar(&options.Check, "check", false, "")
	flags.StringVar(&options.Directory, "metadata", repo.Path("fastlane", "metadata"), "")
	flags.StringVar(&options.Catalog, "catalog", "", "")
	flags.StringVar(&options.ReleaseNotes, "release-notes", "", "")
	if err := flags.Parse(arguments); err != nil || flags.NArg() > 0 {
		return errUsage
	}
	return metadata.Run(options)
}

type fragments []string

func (f *fragments) String() string { return strings.Join(*f, ",") }

func (f *fragments) Set(value string) error {
	*f = append(*f, value)
	return nil
}

func buildWarnings(env environment, arguments []string) error {
	flags := flag.NewFlagSet("build-warnings", flag.ContinueOnError)
	flags.SetOutput(io.Discard)
	ignored := fragments(append([]string{}, buildlog.DefaultIgnored...))
	flags.Var(&ignored, "ignore", "")
	if err := flags.Parse(arguments); err != nil || flags.NArg() == 0 {
		return errUsage
	}
	logs := make([]buildlog.Log, 0, flags.NArg())
	for _, path := range flags.Args() {
		file, err := os.Open(path)
		if err != nil {
			return err
		}
		defer file.Close()
		logs = append(logs, buildlog.Log{Name: path, Reader: file})
	}
	count, err := buildlog.Check(logs, ignored, env.stdout)
	if err != nil {
		return err
	}
	if count > 0 {
		return fmt.Errorf("%d build warnings", count)
	}
	fmt.Fprintf(env.stdout, "no build warnings in %d logs\n", len(logs))
	return nil
}

func appcastHardware(env environment, arguments []string) error {
	if len(arguments) != 2 {
		return errUsage
	}
	data, err := os.ReadFile(arguments[1])
	if err != nil {
		return err
	}
	updated, changed, err := appcast.RequireHardware(string(data), arguments[0])
	if err != nil {
		return err
	}
	if err := os.WriteFile(arguments[1], []byte(updated), 0o644); err != nil {
		return err
	}
	fmt.Fprintf(env.stdout, "required %s on %d appcast items\n", arguments[0], changed)
	return nil
}

func coverageReport(env environment, arguments []string) error {
	flags := flag.NewFlagSet("coverage", flag.ContinueOnError)
	flags.SetOutput(io.Discard)
	root := flags.String("root", repo.Root(), "")
	output := flags.String("output", "", "")
	summaryFile := flags.String("summary-file", os.Getenv("GITHUB_STEP_SUMMARY"), "")
	var minimumValues fragments
	flags.Var(&minimumValues, "min", "")
	if err := flags.Parse(arguments); err != nil || flags.NArg() != 1 {
		return errUsage
	}
	minimums := make([]coverage.Minimum, 0, len(minimumValues))
	for _, value := range minimumValues {
		minimum, err := coverage.ParseMinimum(value)
		if err != nil {
			return err
		}
		minimums = append(minimums, minimum)
	}
	file, err := os.Open(flags.Arg(0))
	if err != nil {
		return err
	}
	defer file.Close()
	report, err := coverage.Parse(file)
	if err != nil {
		return err
	}
	areas := coverage.Summarize(report, *root, coverage.DefaultTargets)
	violations := coverage.Check(areas, minimums)
	markdown := coverage.Markdown(areas, minimums, violations)
	if _, err := io.WriteString(env.stdout, markdown); err != nil {
		return err
	}
	if *output != "" {
		if err := os.WriteFile(*output, []byte(markdown), 0o644); err != nil {
			return err
		}
	}
	if *summaryFile != "" {
		if err := appendToFile(*summaryFile, markdown); err != nil {
			return err
		}
	}
	if len(violations) > 0 {
		return fmt.Errorf("%d coverage minimums not met", len(violations))
	}
	return nil
}

func appendToFile(path, contents string) error {
	file, err := os.OpenFile(path, os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0o644)
	if err != nil {
		return err
	}
	if _, err := io.WriteString(file, contents); err != nil {
		file.Close()
		return err
	}
	return file.Close()
}

func symbolicate(env environment, arguments []string) error {
	flags := flag.NewFlagSet("symbolicate", flag.ContinueOnError)
	flags.SetOutput(io.Discard)
	dsyms := flags.String("dsyms", "", "")
	output := flags.String("output", "", "")
	crashPath, rest := splitPositional(arguments)
	if err := flags.Parse(rest); err != nil || *dsyms == "" {
		return errUsage
	}
	if crashPath == "" && flags.NArg() == 1 {
		crashPath = flags.Arg(0)
	} else if crashPath == "" || flags.NArg() > 0 {
		return errUsage
	}
	data, err := os.ReadFile(crashPath)
	if err != nil {
		return err
	}
	report, err := symbolication.Parse(data)
	if err != nil {
		return err
	}
	directory := *dsyms
	if strings.HasSuffix(strings.ToLower(directory), ".zip") {
		extracted, err := os.MkdirTemp("", "ishare-dsyms-")
		if err != nil {
			return err
		}
		defer os.RemoveAll(extracted)
		if err := symbolication.Unzip(*dsyms, extracted); err != nil {
			return err
		}
		directory = extracted
	}
	bundles, err := symbolication.FindDSYMs(directory)
	if err != nil {
		return err
	}
	if len(bundles) == 0 {
		return fmt.Errorf("no .dSYM bundles found in %s", *dsyms)
	}
	runner := symbolication.ExecRunner{}
	binaries, err := symbolication.IndexBinaries(runner, bundles)
	if err != nil {
		return err
	}
	symbolicated, resolved, err := symbolication.Symbolicate(report, runner, binaries)
	if err != nil {
		return err
	}
	rendered := symbolication.Render(symbolicated)
	if *output != "" {
		if err := os.WriteFile(*output, []byte(rendered), 0o644); err != nil {
			return err
		}
	} else if _, err := io.WriteString(env.stdout, rendered); err != nil {
		return err
	}
	fmt.Fprintf(os.Stderr, "symbolicated %d frames with %d dSYMs\n", resolved, len(bundles))
	return nil
}

func splitPositional(arguments []string) (string, []string) {
	if len(arguments) > 0 && !strings.HasPrefix(arguments[0], "-") {
		return arguments[0], arguments[1:]
	}
	return "", arguments
}
