package coverage

import (
	"encoding/json"
	"fmt"
	"io"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
)

type File struct {
	Path            string `json:"path"`
	Name            string `json:"name"`
	CoveredLines    int    `json:"coveredLines"`
	ExecutableLines int    `json:"executableLines"`
}

type Target struct {
	Name  string `json:"name"`
	Files []File `json:"files"`
}

type Report struct {
	Targets []Target `json:"targets"`
}

var DefaultTargets = []string{"ishare.app", "ishareWidgets.appex", "sharemenuext.appex"}

func Parse(reader io.Reader) (Report, error) {
	var report Report
	if err := json.NewDecoder(reader).Decode(&report); err != nil {
		return Report{}, fmt.Errorf("reading the xccov report: %w", err)
	}
	if len(report.Targets) == 0 {
		return Report{}, fmt.Errorf("the xccov report has no targets")
	}
	return report, nil
}

type Area struct {
	Name       string
	Covered    int
	Executable int
	Files      int
}

func (a Area) Percent() float64 {
	if a.Executable == 0 {
		return 0
	}
	return 100 * float64(a.Covered) / float64(a.Executable)
}

var ISCUFiles = []string{
	"ishare/Util/CustomUploader.swift",
	"ishare/Util/IscuImport.swift",
	"ishare/Util/UploaderValidator.swift",
	"ishare/Util/ShareXImport.swift",
	"ishare/Http/ResponseTemplate.swift",
}

var prefixAreas = []struct {
	prefix string
	area   string
}{
	{"ishare/Views/Editor/", "Editor"},
	{"ishare/Capture/Recording/", "Recording"},
	{"ishare/Capture/", "Capture"},
	{"ishare/Http/", "Http"},
	{"ishareWidgets/", "Widgets"},
	{"sharemenuext/", "Share Extension"},
}

func Classify(relativePath string) string {
	path := strings.TrimPrefix(filepath.ToSlash(relativePath), "/")
	for _, file := range ISCUFiles {
		if path == file {
			return "ISCU"
		}
	}
	for _, rule := range prefixAreas {
		if strings.HasPrefix(path, rule.prefix) {
			return rule.area
		}
	}
	parts := strings.Split(path, "/")
	if len(parts) > 2 && parts[0] == "ishare" {
		return parts[1]
	}
	if len(parts) == 2 && parts[0] == "ishare" {
		return "App"
	}
	if len(parts) > 1 {
		return parts[0]
	}
	return "Other"
}

func Relative(path, root string) string {
	if root == "" {
		return filepath.ToSlash(path)
	}
	relative, err := filepath.Rel(root, path)
	if err != nil || strings.HasPrefix(relative, "..") {
		return filepath.ToSlash(path)
	}
	return filepath.ToSlash(relative)
}

func Summarize(report Report, root string, targets []string) []Area {
	included := map[string]bool{}
	for _, target := range targets {
		included[target] = true
	}
	areas := map[string]*Area{}
	for _, target := range report.Targets {
		if !included[target.Name] {
			continue
		}
		for _, file := range target.Files {
			name := Classify(Relative(file.Path, root))
			area, ok := areas[name]
			if !ok {
				area = &Area{Name: name}
				areas[name] = area
			}
			area.Covered += file.CoveredLines
			area.Executable += file.ExecutableLines
			area.Files++
		}
	}
	result := make([]Area, 0, len(areas))
	for _, area := range areas {
		result = append(result, *area)
	}
	sort.Slice(result, func(i, j int) bool { return result[i].Name < result[j].Name })
	return result
}

func Total(areas []Area) Area {
	total := Area{Name: "Total"}
	for _, area := range areas {
		total.Covered += area.Covered
		total.Executable += area.Executable
		total.Files += area.Files
	}
	return total
}

type Minimum struct {
	Area    string
	Percent float64
}

func ParseMinimum(value string) (Minimum, error) {
	name, percent, found := strings.Cut(value, "=")
	if !found || strings.TrimSpace(name) == "" {
		return Minimum{}, fmt.Errorf("minimum %q must look like Area=percent", value)
	}
	number, err := strconv.ParseFloat(strings.TrimSuffix(strings.TrimSpace(percent), "%"), 64)
	if err != nil || number < 0 || number > 100 {
		return Minimum{}, fmt.Errorf("minimum %q needs a percentage between 0 and 100", value)
	}
	return Minimum{Area: strings.TrimSpace(name), Percent: number}, nil
}

type Violation struct {
	Minimum Minimum
	Actual  float64
	Missing bool
}

func (v Violation) String() string {
	if v.Missing {
		return fmt.Sprintf("%s has no coverage data but needs at least %.1f%%", v.Minimum.Area, v.Minimum.Percent)
	}
	return fmt.Sprintf("%s coverage is %.1f%%, below the minimum of %.1f%%", v.Minimum.Area, v.Actual, v.Minimum.Percent)
}

func Check(areas []Area, minimums []Minimum) []Violation {
	byName := map[string]Area{}
	for _, area := range areas {
		byName[area.Name] = area
	}
	byName["Total"] = Total(areas)
	var violations []Violation
	for _, minimum := range minimums {
		area, ok := byName[minimum.Area]
		if !ok || area.Executable == 0 {
			violations = append(violations, Violation{Minimum: minimum, Missing: true})
			continue
		}
		if rounded(area.Percent()) < minimum.Percent {
			violations = append(violations, Violation{Minimum: minimum, Actual: area.Percent()})
		}
	}
	return violations
}

func rounded(value float64) float64 {
	return float64(int64(value*10+0.5)) / 10
}

const Heading = "### Code coverage"

func Markdown(areas []Area, minimums []Minimum, violations []Violation) string {
	required := map[string]float64{}
	for _, minimum := range minimums {
		required[minimum.Area] = minimum.Percent
	}
	failing := map[string]bool{}
	for _, violation := range violations {
		failing[violation.Minimum.Area] = true
	}
	var builder strings.Builder
	builder.WriteString(Heading + "\n\n")
	builder.WriteString("| Area | Files | Lines | Coverage | Minimum |\n")
	builder.WriteString("| --- | ---: | ---: | ---: | ---: |\n")
	row := func(area Area, bold bool) {
		name := area.Name
		coverage := fmt.Sprintf("%.1f%%", area.Percent())
		if bold {
			name, coverage = "**"+name+"**", "**"+coverage+"**"
		}
		minimum := ""
		if value, ok := required[area.Name]; ok {
			minimum = fmt.Sprintf("%.1f%%", value)
			if failing[area.Name] {
				minimum += " below"
			} else {
				minimum += " met"
			}
		}
		fmt.Fprintf(&builder, "| %s | %d | %d / %d | %s | %s |\n", name, area.Files, area.Covered, area.Executable, coverage, minimum)
	}
	for _, area := range areas {
		row(area, false)
	}
	row(Total(areas), true)
	builder.WriteString("\n")
	if len(violations) == 0 {
		builder.WriteString("Every coverage minimum is met.\n")
	} else {
		for _, violation := range violations {
			builder.WriteString("- " + violation.String() + "\n")
		}
	}
	return builder.String()
}
