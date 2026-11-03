package leaks

import (
	"fmt"
	"regexp"
	"strconv"
	"strings"
)

type Summary struct {
	Leaks int
	Bytes int
}

type Footprint struct {
	Bytes int64
}

type Limits struct {
	MaxLeaks       int
	MaxGrowthBytes int64
}

var leakLine = regexp.MustCompile(`(\d+) leaks? for ([\d,]+) total leaked bytes`)
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
	return Summary{Leaks: count, Bytes: bytes}, nil
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
	if summary.Leaks > limits.MaxLeaks {
		problems = append(problems, fmt.Sprintf("%d leaks (%d bytes), more than the allowed %d", summary.Leaks, summary.Bytes, limits.MaxLeaks))
	}
	if growth := after.Bytes - before.Bytes; growth > limits.MaxGrowthBytes {
		problems = append(problems, fmt.Sprintf("the footprint grew by %.1f MB between identical batches, more than the allowed %.1f MB", float64(growth)/1048576, float64(limits.MaxGrowthBytes)/1048576))
	}
	return problems
}
