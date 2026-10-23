package metadata

import (
	"bytes"
	"errors"
	"fmt"
	"io"
	"io/fs"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"unicode/utf8"

	"github.com/itoolio/ishare/tools/internal/locales"
	"github.com/itoolio/ishare/tools/internal/releasenotes"
	"github.com/itoolio/ishare/tools/internal/xcstrings"
)

const (
	CatalogName      = "Metadata.xcstrings"
	ReleaseNotesFile = "release_notes.txt"
)

type Field struct {
	Name     string
	Limit    int
	InBytes  bool
	Required bool
}

var Fields = []Field{
	{Name: "name", Limit: 30, Required: true},
	{Name: "subtitle", Limit: 30},
	{Name: "keywords", Limit: 100, InBytes: true},
	{Name: "promotional_text", Limit: 170},
	{Name: "description", Limit: 4000, Required: true},
}

var CopiedFiles = []string{"marketing_url.txt", "privacy_url.txt", "support_url.txt"}

var headingKeys = map[string]string{
	"Breaking Changes":         "release_notes.heading.breaking_changes",
	"Features":                 "release_notes.heading.features",
	"Bug Fixes":                "release_notes.heading.bug_fixes",
	"Performance Improvements": "release_notes.heading.performance_improvements",
	"Reverts":                  "release_notes.heading.reverts",
}

const fallbackKey = "release_notes.fallback"

type Catalog struct {
	source  string
	strings *xcstrings.Value
}

func ParseCatalog(data []byte) (Catalog, error) {
	root, err := xcstrings.Parse(data)
	if err != nil {
		return Catalog{}, fmt.Errorf("%s: %w", CatalogName, err)
	}
	entries := root.Get("strings")
	if entries == nil || entries.Kind != xcstrings.Object {
		return Catalog{}, fmt.Errorf("%s has no \"strings\" object", CatalogName)
	}
	source := "en"
	if text, ok := root.Get("sourceLanguage").Text(); ok {
		source = text
	}
	return Catalog{source: source, strings: entries}, nil
}

func (catalog Catalog) Lookup(key, language string) (string, bool) {
	entry := catalog.strings.Get(key)
	if entry == nil {
		return "", false
	}
	value, ok := entry.Get("localizations").Get(language).Get("stringUnit").Get("value").Text()
	if ok && strings.TrimSpace(value) != "" {
		return value, true
	}
	if language == catalog.source {
		return key, true
	}
	return "", false
}

func (catalog Catalog) Text(key, language string) (string, bool) {
	if value, ok := catalog.Lookup(key, language); ok {
		return value, true
	}
	return catalog.Lookup(key, catalog.source)
}

type Files map[string]string

type Rendered struct {
	Locales   map[string]Files
	Fallbacks []string
}

type Input struct {
	Catalog      Catalog
	Copied       Files
	ReleaseNotes string
}

func Render(input Input) Rendered {
	rendered := Rendered{Locales: map[string]Files{}}
	for _, locale := range locales.All {
		files := Files{}
		for _, field := range Fields {
			value, translated := input.Catalog.Lookup(field.Name, locale.Catalog)
			if !translated {
				value, _ = input.Catalog.Text(field.Name, locale.Catalog)
				rendered.Fallbacks = append(rendered.Fallbacks, locale.AppStore+"/"+field.Name)
			}
			if value != "" {
				files[field.Name+".txt"] = strings.TrimSpace(value) + "\n"
			}
		}
		for name, value := range input.Copied {
			files[name] = value
		}
		if input.ReleaseNotes != "" && locale.AppStore != locales.SourceAppStore {
			files[ReleaseNotesFile] = LocalizeReleaseNotes(input.ReleaseNotes, input.Catalog, locale.Catalog) + "\n"
		}
		rendered.Locales[locale.AppStore] = files
	}
	return rendered
}

func LocalizeReleaseNotes(notes string, catalog Catalog, language string) string {
	lines := strings.Split(strings.TrimSpace(notes), "\n")
	for index, line := range lines {
		trimmed := strings.TrimSpace(line)
		if heading, ok := strings.CutSuffix(trimmed, ":"); ok {
			if key, known := headingKeys[heading]; known {
				lines[index] = translated(catalog, key, language, heading) + ":"
				continue
			}
		}
		if trimmed == releasenotes.Fallback {
			lines[index] = translated(catalog, fallbackKey, language, trimmed)
			continue
		}
		if text, ok := strings.CutPrefix(trimmed, "• "); ok {
			if value, found := catalog.Lookup(text, language); found {
				lines[index] = "• " + value
			}
		}
	}
	return strings.Join(lines, "\n")
}

func translated(catalog Catalog, key, language, english string) string {
	if value, ok := catalog.Lookup(key, language); ok {
		return value
	}
	return english
}

func Length(field Field, value string) int {
	if field.InBytes {
		return len(value)
	}
	return utf8.RuneCountInString(value)
}

func Problems(locale string, files Files) []string {
	var problems []string
	for _, field := range Fields {
		value, present := files[field.Name+".txt"]
		value = strings.TrimSpace(value)
		if !present || value == "" {
			if field.Required {
				problems = append(problems, fmt.Sprintf("%s/%s.txt is missing", locale, field.Name))
			}
			continue
		}
		unit := "characters"
		if field.InBytes {
			unit = "bytes"
		}
		if length := Length(field, value); length > field.Limit {
			problems = append(problems, fmt.Sprintf("%s/%s.txt is %d %s long, the App Store allows %d", locale, field.Name, length, unit, field.Limit))
		}
		if field.Name == "keywords" {
			problems = append(problems, keywordProblems(locale, value)...)
		}
		if field.Name != "description" && strings.Contains(value, "\n") {
			problems = append(problems, fmt.Sprintf("%s/%s.txt must be a single line", locale, field.Name))
		}
	}
	if notes, present := files[ReleaseNotesFile]; present {
		for _, problem := range releasenotes.Problems(notes) {
			problems = append(problems, fmt.Sprintf("%s/%s: %s", locale, ReleaseNotesFile, problem))
		}
	}
	return problems
}

func keywordProblems(locale, keywords string) []string {
	var problems []string
	seen := map[string]bool{}
	for _, keyword := range strings.Split(keywords, ",") {
		keyword = strings.ToLower(strings.TrimSpace(keyword))
		if keyword == "" {
			problems = append(problems, fmt.Sprintf("%s/keywords.txt has an empty keyword", locale))
			continue
		}
		if seen[keyword] {
			problems = append(problems, fmt.Sprintf("%s/keywords.txt repeats %q", locale, keyword))
		}
		seen[keyword] = true
	}
	return problems
}

type Options struct {
	Directory    string
	Catalog      string
	ReleaseNotes string
	Check        bool
	Output       io.Writer
}

func Run(options Options) error {
	if options.Catalog == "" {
		options.Catalog = filepath.Join(options.Directory, CatalogName)
	}
	data, err := os.ReadFile(options.Catalog)
	if err != nil {
		return err
	}
	catalog, err := ParseCatalog(data)
	if err != nil {
		return err
	}
	source := filepath.Join(options.Directory, locales.SourceAppStore)
	copied, err := readFiles(source, CopiedFiles)
	if err != nil {
		return err
	}
	notesPath := options.ReleaseNotes
	if notesPath == "" {
		notesPath = filepath.Join(source, ReleaseNotesFile)
	}
	notes, err := os.ReadFile(notesPath)
	if err != nil && !errors.Is(err, fs.ErrNotExist) {
		return err
	}
	rendered := Render(Input{Catalog: catalog, Copied: copied, ReleaseNotes: string(notes)})
	var problems []string
	var stale []string
	for _, code := range locales.AppStoreCodes() {
		files := rendered.Locales[code]
		problems = append(problems, Problems(code, files)...)
		changed, err := sync(filepath.Join(options.Directory, code), files, options.Check)
		if err != nil {
			return err
		}
		for _, name := range changed {
			stale = append(stale, code+"/"+name)
		}
	}
	for _, fallback := range rendered.Fallbacks {
		fmt.Fprintf(options.Output, "note %s has no translation yet and uses the English text\n", fallback)
	}
	if len(problems) > 0 {
		return fmt.Errorf("the App Store metadata breaks the limits:\n  - %s", strings.Join(problems, "\n  - "))
	}
	if options.Check {
		if len(stale) > 0 {
			return fmt.Errorf("the App Store metadata is out of date with %s, run ishare-tools metadata:\n  - %s", CatalogName, strings.Join(stale, "\n  - "))
		}
		fmt.Fprintf(options.Output, "The metadata of %d locales matches %s\n", len(locales.All), CatalogName)
		return nil
	}
	fmt.Fprintf(options.Output, "Wrote the metadata of %d locales, %d files changed\n", len(locales.All), len(stale))
	return nil
}

func readFiles(directory string, names []string) (Files, error) {
	files := Files{}
	for _, name := range names {
		data, err := os.ReadFile(filepath.Join(directory, name))
		if errors.Is(err, fs.ErrNotExist) {
			continue
		}
		if err != nil {
			return nil, err
		}
		files[name] = string(data)
	}
	return files, nil
}

func sync(directory string, files Files, check bool) ([]string, error) {
	names := make([]string, 0, len(files))
	for name := range files {
		names = append(names, name)
	}
	sort.Strings(names)
	var changed []string
	for _, name := range names {
		path := filepath.Join(directory, name)
		current, err := os.ReadFile(path)
		if err == nil && bytes.Equal(current, []byte(files[name])) {
			continue
		}
		if err != nil && !errors.Is(err, fs.ErrNotExist) {
			return nil, err
		}
		changed = append(changed, name)
		if check {
			continue
		}
		if err := os.MkdirAll(directory, 0o755); err != nil {
			return nil, err
		}
		if err := os.WriteFile(path, []byte(files[name]), 0o644); err != nil {
			return nil, err
		}
	}
	return changed, nil
}

func CheckDirectory(directory string) []string {
	var problems []string
	for _, code := range locales.AppStoreCodes() {
		names := []string{ReleaseNotesFile}
		for _, field := range Fields {
			names = append(names, field.Name+".txt")
		}
		files, err := readFiles(filepath.Join(directory, code), names)
		if err != nil {
			problems = append(problems, err.Error())
			continue
		}
		problems = append(problems, Problems(code, files)...)
	}
	return problems
}
