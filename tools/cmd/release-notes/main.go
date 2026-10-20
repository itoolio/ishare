package main

import (
	"bufio"
	"fmt"
	"io"
	"os"
	"regexp"
	"strings"

	"github.com/itoolio/ishare/tools/internal/repo"
)

const appStoreLimit = 4000

var (
	versionHeading = regexp.MustCompile(`^#{1,2}\s`)
	sectionHeading = regexp.MustCompile(`^#{3,}\s+(.*)$`)
	bullet         = regexp.MustCompile(`^\s*[*-]\s+(.*)$`)
	scope          = regexp.MustCompile(`^\*\*([^*]+):\*\*\s*`)
	links          = regexp.MustCompile(`\s*\(\[[0-9a-f]{7,40}\]\([^)]*\)\)`)
	issueRefs      = regexp.MustCompile(`,?\s*(closes|fixes|resolves)\s+\[#\d+\]\([^)]*\)((,\s*|\s+)\[#\d+\]\([^)]*\))*`)
	markdownLink   = regexp.MustCompile(`\[([^\]]+)\]\([^)]*\)`)
	emphasis       = regexp.MustCompile("[*_`]+")
)

func main() {
	input, err := io.ReadAll(os.Stdin)
	if err != nil {
		repo.Fail(err)
	}
	notes := Convert(string(input))
	if notes == "" {
		notes = "Bug fixes and improvements."
	}
	if len(os.Args) > 1 {
		if err := os.WriteFile(os.Args[1], []byte(notes+"\n"), 0o644); err != nil {
			repo.Fail(err)
		}
		return
	}
	fmt.Println(notes)
}

func Convert(markdown string) string {
	var lines []string
	scanner := bufio.NewScanner(strings.NewReader(markdown))
	for scanner.Scan() {
		line := strings.TrimRight(scanner.Text(), " ")
		switch {
		case strings.TrimSpace(line) == "", versionHeading.MatchString(line):
			continue
		case sectionHeading.MatchString(line):
			title := sectionHeading.FindStringSubmatch(line)[1]
			if len(lines) > 0 {
				lines = append(lines, "")
			}
			lines = append(lines, strings.TrimSpace(clean(title))+":")
		case bullet.MatchString(line):
			text := bullet.FindStringSubmatch(line)[1]
			text = scope.ReplaceAllString(text, "")
			text = clean(text)
			if text != "" {
				lines = append(lines, "• "+upperFirst(text))
			}
		default:
			lines = append(lines, clean(line))
		}
	}
	return truncate(strings.TrimSpace(strings.Join(lines, "\n")), appStoreLimit)
}

func clean(text string) string {
	text = links.ReplaceAllString(text, "")
	text = issueRefs.ReplaceAllString(text, "")
	text = markdownLink.ReplaceAllString(text, "$1")
	text = emphasis.ReplaceAllString(text, "")
	return strings.TrimSpace(text)
}

func upperFirst(text string) string {
	if text == "" {
		return text
	}
	runes := []rune(text)
	runes[0] = []rune(strings.ToUpper(string(runes[0])))[0]
	return string(runes)
}

func truncate(text string, limit int) string {
	if len([]rune(text)) <= limit {
		return text
	}
	runes := []rune(text)[:limit-1]
	cut := strings.LastIndex(string(runes), "\n")
	if cut > 0 {
		return string(runes)[:cut] + "\n…"
	}
	return string(runes) + "…"
}
