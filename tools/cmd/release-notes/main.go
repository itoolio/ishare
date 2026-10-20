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
	prNumber       = regexp.MustCompile(`\s*\(#\d+\)$`)
	trailer        = regexp.MustCompile(`^(Co-Authored-By|Signed-off-by|Reviewed-by|Refs?|Closes|Fixes):`)
	angleBracketed = regexp.MustCompile(`<[^>]*>`)
	disallowed     = regexp.MustCompile(`[^\p{L}\p{N}\p{P}\p{Zs}•…+=$€£%]`)
)

var sectionTitles = map[string]string{
	"breaking changes":         "Breaking Changes",
	"features":                 "Features",
	"bug fixes":                "Bug Fixes",
	"performance improvements": "Performance Improvements",
	"reverts":                  "Reverts",
}

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
	seen := map[string]bool{}
	include := false
	scanner := bufio.NewScanner(strings.NewReader(markdown))
	for scanner.Scan() {
		line := strings.TrimRight(scanner.Text(), " ")
		switch {
		case strings.TrimSpace(line) == "", versionHeading.MatchString(line):
			continue
		case sectionHeading.MatchString(line):
			title, known := sectionTitle(sectionHeading.FindStringSubmatch(line)[1])
			include = known
			if !include {
				continue
			}
			if len(lines) > 0 {
				lines = append(lines, "")
			}
			lines = append(lines, title+":")
		case !include, trailer.MatchString(strings.TrimSpace(line)):
			continue
		case bullet.MatchString(line):
			text := bullet.FindStringSubmatch(line)[1]
			text = upperFirst(clean(scope.ReplaceAllString(text, "")))
			if text != "" && !seen[text] {
				seen[text] = true
				lines = append(lines, "• "+text)
			}
		default:
			if text := clean(line); text != "" {
				lines = append(lines, text)
			}
		}
	}
	return truncate(strings.TrimSpace(strings.Join(lines, "\n")), appStoreLimit)
}

func sectionTitle(heading string) (string, bool) {
	key := strings.ToLower(strings.TrimSpace(disallowed.ReplaceAllString(clean(heading), "")))
	title, known := sectionTitles[key]
	return title, known
}

func clean(text string) string {
	text = links.ReplaceAllString(text, "")
	text = issueRefs.ReplaceAllString(text, "")
	text = markdownLink.ReplaceAllString(text, "$1")
	text = emphasis.ReplaceAllString(text, "")
	text = angleBracketed.ReplaceAllString(text, "")
	text = disallowed.ReplaceAllString(text, "")
	text = prNumber.ReplaceAllString(strings.TrimSpace(text), "")
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
