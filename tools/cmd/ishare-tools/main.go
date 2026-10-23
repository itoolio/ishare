package main

import (
	"errors"
	"flag"
	"fmt"
	"io"
	"os"
	"sort"
	"strings"

	"github.com/itoolio/ishare/tools/internal/appstore"
	"github.com/itoolio/ishare/tools/internal/releasecheck"
	"github.com/itoolio/ishare/tools/internal/releasenotes"
	"github.com/itoolio/ishare/tools/internal/repo"
	"github.com/itoolio/ishare/tools/internal/screenshots"
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
	"screenshots":        {"screenshots [--ci] [locale[:language]...]", captureScreenshots},
	"release-check":      {"release-check [--app ishare.app|ishare.xcarchive] [--release-notes file] [--allowlist file] [--review-notes file] [--screenshots dir]", releaseCheck},
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
	targets, err := screenshots.ParseTargets(arguments)
	if err != nil {
		return err
	}
	return screenshots.Run(screenshots.Options{Root: repo.Root(), Targets: targets, Output: env.stdout})
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
	if err := flags.Parse(arguments); err != nil || flags.NArg() > 0 {
		return errUsage
	}
	_, err := releasecheck.Run(options)
	return err
}
