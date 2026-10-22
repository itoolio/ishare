package version

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
	semanticVersion  = regexp.MustCompile(`^\d+\.\d+\.\d+([-+][0-9A-Za-z.-]+)?$`)
)

func Apply(config []byte, version, build string) ([]byte, error) {
	if !semanticVersion.MatchString(version) {
		return nil, fmt.Errorf("%q is not a semantic version", version)
	}
	if !marketingVersion.Match(config) || !buildNumber.Match(config) {
		return nil, fmt.Errorf("the configuration needs MARKETING_VERSION and CURRENT_PROJECT_VERSION lines")
	}
	updated := marketingVersion.ReplaceAllLiteral(config, []byte("MARKETING_VERSION = "+version))
	return buildNumber.ReplaceAllLiteral(updated, []byte("CURRENT_PROJECT_VERSION = "+build)), nil
}

func Set(version string) (string, error) {
	path := repo.Path("Config.xcconfig")
	contents, err := os.ReadFile(path)
	if err != nil {
		return "", err
	}
	build, err := commitCount()
	if err != nil {
		return "", err
	}
	updated, err := Apply(contents, version, build)
	if err != nil {
		return "", fmt.Errorf("%s: %w", path, err)
	}
	if err := os.WriteFile(path, updated, 0o644); err != nil {
		return "", err
	}
	return build, nil
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
