package releasenotes

import (
	"bufio"
	"fmt"
	"regexp"
	"strings"
)

const (
	appStoreLimit = 4000
	fallback      = "Bug fixes and improvements."
)

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

var sectionOrder = []string{"Breaking Changes", "Features", "Bug Fixes", "Performance Improvements", "Reverts"}

func Render(markdown string) string {
	if notes := Convert(markdown); notes != "" {
		return notes
	}
	return fallback
}

func Convert(markdown string) string {
	sections := map[string][]string{}
	seen := map[string]bool{}
	current := ""
	scanner := bufio.NewScanner(strings.NewReader(markdown))
	for scanner.Scan() {
		line := strings.TrimRight(scanner.Text(), " ")
		switch {
		case strings.TrimSpace(line) == "", versionHeading.MatchString(line):
			continue
		case sectionHeading.MatchString(line):
			title, known := sectionTitle(sectionHeading.FindStringSubmatch(line)[1])
			current = ""
			if known {
				current = title
			}
		case current == "", trailer.MatchString(strings.TrimSpace(line)):
			continue
		case bullet.MatchString(line):
			text := bullet.FindStringSubmatch(line)[1]
			text = upperFirst(clean(scope.ReplaceAllString(text, "")))
			if text != "" && !seen[text] {
				seen[text] = true
				sections[current] = append(sections[current], "• "+text)
			}
		default:
			if text := clean(line); text != "" {
				sections[current] = append(sections[current], text)
			}
		}
	}
	var blocks []string
	for _, title := range sectionOrder {
		if lines := sections[title]; len(lines) > 0 {
			blocks = append(blocks, title+":\n"+strings.Join(lines, "\n"))
		}
	}
	return truncate(strings.Join(blocks, "\n\n"), appStoreLimit)
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

var markup = regexp.MustCompile("[*_`#<>\\[\\]]")

func Problems(notes string) []string {
	var problems []string
	trimmed := strings.TrimSpace(notes)
	if trimmed == "" {
		problems = append(problems, "the release notes are empty")
	}
	if length := len([]rune(trimmed)); length > appStoreLimit {
		problems = append(problems, fmt.Sprintf("the release notes are %d characters long, the App Store allows %d", length, appStoreLimit))
	}
	for number, line := range strings.Split(trimmed, "\n") {
		if markup.MatchString(line) {
			problems = append(problems, fmt.Sprintf("line %d contains Markdown markup: %q", number+1, line))
		}
		if symbols := disallowed.FindAllString(line, -1); len(symbols) > 0 {
			problems = append(problems, fmt.Sprintf("line %d contains symbols the App Store may reject: %q", number+1, strings.Join(symbols, "")))
		}
	}
	return problems
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
