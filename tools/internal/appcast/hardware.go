package appcast

import (
	"fmt"
	"regexp"
	"strings"
)

var itemPattern = regexp.MustCompile(`(?s)<item>.*?</item>`)

func RequireHardware(feed string, requirement string) (string, int, error) {
	if strings.TrimSpace(requirement) == "" {
		return "", 0, fmt.Errorf("the hardware requirement is empty")
	}
	if !strings.Contains(feed, "<item>") {
		return "", 0, fmt.Errorf("the appcast has no items")
	}
	element := fmt.Sprintf("<sparkle:hardwareRequirements>%s</sparkle:hardwareRequirements>", requirement)
	changed := 0
	updated := itemPattern.ReplaceAllStringFunc(feed, func(item string) string {
		if strings.Contains(item, "<sparkle:hardwareRequirements>") {
			return item
		}
		changed++
		closing := strings.LastIndex(item, "</item>")
		indent := indentation(item[:closing])
		return item[:closing] + "    " + element + "\n" + indent + item[closing:]
	})
	return updated, changed, nil
}

func indentation(prefix string) string {
	line := prefix[strings.LastIndex(prefix, "\n")+1:]
	return line[:len(line)-len(strings.TrimLeft(line, " \t"))]
}
