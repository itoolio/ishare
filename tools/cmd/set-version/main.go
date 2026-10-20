package main

import (
	"fmt"
	"os"
	"os/exec"
	"regexp"
	"strings"

	"github.com/itoolio/ishare/tools/internal/repo"
)

var (
	marketingVersion = regexp.MustCompile(`(?m)^MARKETING_VERSION = .*$`)
	buildNumber      = regexp.MustCompile(`(?m)^CURRENT_PROJECT_VERSION = .*$`)
)

func main() {
	if len(os.Args) != 2 {
		repo.Fail(fmt.Errorf("usage: set-version <version>"))
	}
	version := os.Args[1]
	config := repo.Path("Config.xcconfig")
	contents, err := os.ReadFile(config)
	if err != nil {
		repo.Fail(err)
	}
	if !marketingVersion.Match(contents) || !buildNumber.Match(contents) {
		repo.Fail(fmt.Errorf("%s needs MARKETING_VERSION and CURRENT_PROJECT_VERSION lines", config))
	}
	build, err := commitCount()
	if err != nil {
		repo.Fail(err)
	}
	updated := marketingVersion.ReplaceAll(contents, []byte("MARKETING_VERSION = "+version))
	updated = buildNumber.ReplaceAll(updated, []byte("CURRENT_PROJECT_VERSION = "+build))
	if err := os.WriteFile(config, updated, 0o644); err != nil {
		repo.Fail(err)
	}
	fmt.Printf("version %s (%s)\n", version, build)
}

func commitCount() (string, error) {
	command := exec.Command("git", "rev-list", "--count", "HEAD")
	command.Dir = repo.Root()
	output, err := command.Output()
	if err != nil {
		return "", fmt.Errorf("couldn't count commits: %w", err)
	}
	return strings.TrimSpace(string(output)), nil
}
