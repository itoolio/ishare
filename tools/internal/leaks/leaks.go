package leaks

import (
	"fmt"
	"regexp"
	"strconv"
	"strings"
)

type Summary struct {
	Leaks       int
	Bytes       int
	SystemLeaks int
	SystemBytes int
}

type Footprint struct {
	Bytes int64
}

type Limits struct {
	MaxLeaks       int
	MaxGrowthBytes int64
}

var leakLine = regexp.MustCompile(`(\d+) leaks? for ([\d,]+) total leaked bytes`)
var rootLine = regexp.MustCompile(`^( *)(\d+) \(([\d.]+)\s*(bytes|K|M)\) ROOT (?:LEAK|CYCLE): (.*)$`)
var systemServiceRoots = []string{`"com.apple.linkd.`}
var footprintLine = regexp.MustCompile(`(?i)phys_footprint:\s*([\d.]+)\s*([KMG]?B)`)

func ParseLeaks(output string) (Summary, error) {
	match := leakLine.FindStringSubmatch(output)
	if match == nil {
		if strings.Contains(output, "0 leaks for 0 total leaked bytes") {
			return Summary{}, nil
		}
		return Summary{}, fmt.Errorf("no leak summary in the leaks output")
	}
	count, _ := strconv.Atoi(match[1])
	bytes, _ := strconv.Atoi(strings.ReplaceAll(match[2], ",", ""))
	systemLeaks, systemBytes := systemFrameworkLeaks(output)
	return Summary{Leaks: count, Bytes: bytes, SystemLeaks: systemLeaks, SystemBytes: systemBytes}, nil
}

type leakRoot struct {
	depth       int
	leaks       int
	bytes       int
	description string
}

func systemFrameworkLeaks(output string) (int, int) {
	leaks, bytes := 0, 0
	for _, section := range strings.Split(output, "\nSTACK OF ") {
		sectionLeaks, sectionBytes := systemFrameworkLeaksInSection(section)
		leaks += sectionLeaks
		bytes += sectionBytes
	}
	return leaks, bytes
}

func systemFrameworkLeaksInSection(section string) (int, int) {
	var roots []leakRoot
	topDepth := -1
	for _, line := range strings.Split(section, "\n") {
		match := rootLine.FindStringSubmatch(line)
		if match == nil {
			continue
		}
		count, _ := strconv.Atoi(match[2])
		root := leakRoot{depth: len(match[1]), leaks: count, bytes: sizeInBytes(match[3], match[4]), description: match[5]}
		roots = append(roots, root)
		if topDepth < 0 || root.depth < topDepth {
			topDepth = root.depth
		}
	}
	leaks, bytes := 0, 0
	for _, root := range roots {
		if root.depth == topDepth && holdsSystemServiceConnection(root.description) {
			leaks += root.leaks
			bytes += root.bytes
		}
	}
	return leaks, bytes
}

func holdsSystemServiceConnection(description string) bool {
	for _, service := range systemServiceRoots {
		if strings.Contains(description, service) {
			return true
		}
	}
	return false
}

func sizeInBytes(value, unit string) int {
	amount, _ := strconv.ParseFloat(value, 64)
	return int(amount * map[string]float64{"bytes": 1, "K": 1024, "M": 1024 * 1024}[unit])
}

func (summary Summary) OwnLeaks() int {
	return summary.Leaks - summary.SystemLeaks
}

func ParseFootprint(output string) (Footprint, error) {
	match := footprintLine.FindStringSubmatch(output)
	if match == nil {
		return Footprint{}, fmt.Errorf("no phys_footprint in the footprint output")
	}
	value, err := strconv.ParseFloat(match[1], 64)
	if err != nil {
		return Footprint{}, err
	}
	multiplier := map[string]float64{"B": 1, "KB": 1024, "MB": 1024 * 1024, "GB": 1024 * 1024 * 1024}[strings.ToUpper(match[2])]
	return Footprint{Bytes: int64(value * multiplier)}, nil
}

func Check(summary Summary, before, after Footprint, limits Limits) []string {
	var problems []string
	if summary.OwnLeaks() > limits.MaxLeaks {
		problems = append(problems, fmt.Sprintf("%d leaks (%d bytes), more than the allowed %d", summary.OwnLeaks(), summary.Bytes-summary.SystemBytes, limits.MaxLeaks))
	}
	if growth := after.Bytes - before.Bytes; growth > limits.MaxGrowthBytes {
		problems = append(problems, fmt.Sprintf("the footprint grew by %.1f MB between identical batches, more than the allowed %.1f MB", float64(growth)/1048576, float64(limits.MaxGrowthBytes)/1048576))
	}
	return problems
}
