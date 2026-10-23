package buildlog

import (
	"bufio"
	"fmt"
	"io"
	"regexp"
	"strings"
)

var DefaultIgnored = []string{"/SourcePackages/checkouts/"}

var warningLine = regexp.MustCompile(`\b(warning|WARNING):`)

func Warnings(log io.Reader, ignored []string) ([]string, error) {
	scanner := bufio.NewScanner(log)
	scanner.Buffer(make([]byte, 0, 64*1024), 16*1024*1024)
	seen := map[string]bool{}
	var warnings []string
	for scanner.Scan() {
		line := strings.TrimRight(scanner.Text(), "\r")
		if !isWarning(line) || isIgnored(line, ignored) || seen[line] {
			continue
		}
		seen[line] = true
		warnings = append(warnings, line)
	}
	return warnings, scanner.Err()
}

type Log struct {
	Name   string
	Reader io.Reader
}

func Check(logs []Log, ignored []string, output io.Writer) (int, error) {
	total := 0
	for _, log := range logs {
		warnings, err := Warnings(log.Reader, ignored)
		if err != nil {
			return total, fmt.Errorf("%s: %w", log.Name, err)
		}
		for _, warning := range warnings {
			fmt.Fprintf(output, "::error title=Build warning in %s::%s\n", log.Name, warning)
		}
		total += len(warnings)
	}
	return total, nil
}

func isWarning(line string) bool {
	if line == "" || line[0] == ' ' || line[0] == '\t' {
		return false
	}
	return warningLine.MatchString(line)
}

func isIgnored(line string, ignored []string) bool {
	for _, fragment := range ignored {
		if fragment != "" && strings.Contains(line, fragment) {
			return true
		}
	}
	return false
}
