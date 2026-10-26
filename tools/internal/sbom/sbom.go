package sbom

import (
	"bufio"
	"bytes"
	"encoding/json"
	"fmt"
	"net/url"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
	"time"
)

const (
	spdxVersion   = "SPDX-2.3"
	dataLicense   = "CC0-1.0"
	noAssertion   = "NOASSERTION"
	rootID        = "SPDXRef-Package-ishare"
	documentID    = "SPDXRef-DOCUMENT"
	repository    = "itoolio/ishare"
	namespaceBase = "https://github.com/itoolio/ishare/releases/download"
	toolName      = "ishare-tools-sbom"
)

type Component struct {
	Name             string
	Version          string
	Revision         string
	DownloadLocation string
	PURL             string
	Ecosystem        string
}

type Options struct {
	Version         string
	PackageResolved []string
	PackageDirs     []string
	GoModules       []string
	Created         time.Time
}

type Document struct {
	SPDXID            string         `json:"SPDXID"`
	SPDXVersion       string         `json:"spdxVersion"`
	DataLicense       string         `json:"dataLicense"`
	Name              string         `json:"name"`
	DocumentNamespace string         `json:"documentNamespace"`
	CreationInfo      CreationInfo   `json:"creationInfo"`
	DocumentDescribes []string       `json:"documentDescribes"`
	Packages          []Package      `json:"packages"`
	Relationships     []Relationship `json:"relationships"`
}

type CreationInfo struct {
	Created  string   `json:"created"`
	Creators []string `json:"creators"`
}

type Package struct {
	SPDXID           string        `json:"SPDXID"`
	Name             string        `json:"name"`
	VersionInfo      string        `json:"versionInfo,omitempty"`
	Supplier         string        `json:"supplier"`
	DownloadLocation string        `json:"downloadLocation"`
	FilesAnalyzed    bool          `json:"filesAnalyzed"`
	LicenseConcluded string        `json:"licenseConcluded"`
	LicenseDeclared  string        `json:"licenseDeclared"`
	CopyrightText    string        `json:"copyrightText"`
	PrimaryPurpose   string        `json:"primaryPackagePurpose,omitempty"`
	Comment          string        `json:"comment,omitempty"`
	ExternalRefs     []ExternalRef `json:"externalRefs,omitempty"`
}

type ExternalRef struct {
	ReferenceCategory string `json:"referenceCategory"`
	ReferenceType     string `json:"referenceType"`
	ReferenceLocator  string `json:"referenceLocator"`
}

type Relationship struct {
	SPDXElementID      string `json:"spdxElementId"`
	RelationshipType   string `json:"relationshipType"`
	RelatedSPDXElement string `json:"relatedSpdxElement"`
}

type resolvedFile struct {
	Version int           `json:"version"`
	Pins    []resolvedPin `json:"pins"`
	Object  struct {
		Pins []resolvedPin `json:"pins"`
	} `json:"object"`
}

type resolvedPin struct {
	Identity      string        `json:"identity"`
	Package       string        `json:"package"`
	Location      string        `json:"location"`
	RepositoryURL string        `json:"repositoryURL"`
	State         resolvedState `json:"state"`
}

type resolvedState struct {
	Version  *string `json:"version"`
	Revision string  `json:"revision"`
	Branch   *string `json:"branch"`
}

func ParsePackageResolved(data []byte) ([]Component, error) {
	var file resolvedFile
	if err := json.Unmarshal(data, &file); err != nil {
		return nil, fmt.Errorf("couldn't read Package.resolved: %w", err)
	}
	pins := file.Pins
	if file.Version == 1 || len(pins) == 0 {
		pins = append(pins, file.Object.Pins...)
	}
	components := make([]Component, 0, len(pins))
	for _, pin := range pins {
		location := firstNonEmpty(pin.Location, pin.RepositoryURL)
		name := strings.ToLower(firstNonEmpty(pin.Identity, pin.Package, repositoryName(location)))
		if name == "" {
			return nil, fmt.Errorf("a pin in Package.resolved has no identity")
		}
		version := ""
		if pin.State.Version != nil {
			version = *pin.State.Version
		}
		components = append(components, Component{
			Name:             name,
			Version:          firstNonEmpty(version, pin.State.Revision),
			Revision:         pin.State.Revision,
			DownloadLocation: downloadLocation(location),
			PURL:             swiftPURL(location, name, firstNonEmpty(version, pin.State.Revision)),
			Ecosystem:        "swift",
		})
	}
	return components, nil
}

var packageNamePattern = regexp.MustCompile(`(?s)Package\s*\(\s*name:\s*"([^"]+)"`)

func ParseLocalPackage(directory, version string) (Component, error) {
	manifest, err := os.ReadFile(filepath.Join(directory, "Package.swift"))
	if err != nil {
		return Component{}, err
	}
	match := packageNamePattern.FindSubmatch(manifest)
	if match == nil {
		return Component{}, fmt.Errorf("%s has no package name", filepath.Join(directory, "Package.swift"))
	}
	name := string(match[1])
	return Component{
		Name:             name,
		Version:          version,
		DownloadLocation: noAssertion,
		PURL:             "pkg:swift/github.com/" + repository + "@v" + version + "#" + filepath.ToSlash(filepath.Clean(directory)),
		Ecosystem:        "swift-local",
	}, nil
}

func ParseGoMod(data []byte) ([]Component, error) {
	var components []Component
	scanner := bufio.NewScanner(bytes.NewReader(data))
	inBlock := false
	line := 0
	for scanner.Scan() {
		line++
		text := strings.TrimSpace(stripGoComment(scanner.Text()))
		switch {
		case text == "":
			continue
		case inBlock && text == ")":
			inBlock = false
			continue
		case !inBlock && (text == "require (" || text == "require("):
			inBlock = true
			continue
		case inBlock:
		case strings.HasPrefix(text, "require "):
			text = strings.TrimSpace(strings.TrimPrefix(text, "require "))
		default:
			continue
		}
		fields := strings.Fields(text)
		if len(fields) < 2 {
			return nil, fmt.Errorf("go.mod line %d: malformed requirement %q", line, text)
		}
		path, version := fields[0], fields[1]
		components = append(components, Component{
			Name:             path,
			Version:          version,
			DownloadLocation: "https://proxy.golang.org/" + escapeModulePath(path) + "/@v/" + version + ".zip",
			PURL:             "pkg:golang/" + path + "@" + version,
			Ecosystem:        "go",
		})
	}
	if err := scanner.Err(); err != nil {
		return nil, err
	}
	if inBlock {
		return nil, fmt.Errorf("go.mod has an unterminated require block")
	}
	return components, nil
}

func ParseGoModule(data []byte) (string, error) {
	scanner := bufio.NewScanner(bytes.NewReader(data))
	for scanner.Scan() {
		text := strings.TrimSpace(stripGoComment(scanner.Text()))
		if strings.HasPrefix(text, "module ") {
			return strings.Trim(strings.TrimSpace(strings.TrimPrefix(text, "module ")), `"`), nil
		}
	}
	return "", fmt.Errorf("go.mod has no module line")
}

func Collect(options Options) ([]Component, error) {
	var components []Component
	for _, path := range options.PackageResolved {
		data, err := os.ReadFile(path)
		if err != nil {
			return nil, err
		}
		parsed, err := ParsePackageResolved(data)
		if err != nil {
			return nil, fmt.Errorf("%s: %w", path, err)
		}
		components = append(components, parsed...)
	}
	for _, directory := range options.PackageDirs {
		local, err := ParseLocalPackage(directory, options.Version)
		if err != nil {
			return nil, err
		}
		components = append(components, local)
	}
	for _, path := range options.GoModules {
		data, err := os.ReadFile(path)
		if err != nil {
			return nil, err
		}
		module, err := ParseGoModule(data)
		if err != nil {
			return nil, fmt.Errorf("%s: %w", path, err)
		}
		components = append(components, Component{
			Name:             module,
			Version:          options.Version,
			DownloadLocation: noAssertion,
			PURL:             "pkg:golang/" + module + "@v" + options.Version,
			Ecosystem:        "go-local",
		})
		requirements, err := ParseGoMod(data)
		if err != nil {
			return nil, fmt.Errorf("%s: %w", path, err)
		}
		components = append(components, requirements...)
	}
	return dedupe(components), nil
}

func Build(version string, components []Component, created time.Time) (Document, error) {
	if version == "" {
		return Document{}, fmt.Errorf("the version is empty")
	}
	sorted := dedupe(components)
	root := Package{
		SPDXID:           rootID,
		Name:             "ishare",
		VersionInfo:      version,
		Supplier:         "Organization: itoolio",
		DownloadLocation: "https://github.com/" + repository + "/releases/download/v" + version + "/ishare.dmg",
		LicenseConcluded: noAssertion,
		LicenseDeclared:  "GPL-3.0-only",
		CopyrightText:    "Copyright Adrian Castro",
		PrimaryPurpose:   "APPLICATION",
		ExternalRefs:     []ExternalRef{purlRef("pkg:github/" + repository + "@v" + version)},
	}
	document := Document{
		SPDXID:            documentID,
		SPDXVersion:       spdxVersion,
		DataLicense:       dataLicense,
		Name:              "ishare-" + version,
		DocumentNamespace: namespaceBase + "/v" + version + "/ishare-" + version + "-sbom.spdx.json",
		CreationInfo: CreationInfo{
			Created:  created.UTC().Format(time.RFC3339),
			Creators: []string{"Organization: itoolio", "Tool: " + toolName},
		},
		DocumentDescribes: []string{rootID},
		Packages:          []Package{root},
		Relationships:     []Relationship{{SPDXElementID: documentID, RelationshipType: "DESCRIBES", RelatedSPDXElement: rootID}},
	}
	used := map[string]bool{rootID: true}
	for _, component := range sorted {
		id := uniqueID(spdxID(component), used)
		pkg := Package{
			SPDXID:           id,
			Name:             component.Name,
			VersionInfo:      component.Version,
			Supplier:         noAssertion,
			DownloadLocation: firstNonEmpty(component.DownloadLocation, noAssertion),
			LicenseConcluded: noAssertion,
			LicenseDeclared:  noAssertion,
			CopyrightText:    noAssertion,
			PrimaryPurpose:   "LIBRARY",
		}
		if component.Revision != "" && component.Revision != component.Version {
			pkg.Comment = "revision " + component.Revision
		}
		if component.PURL != "" {
			pkg.ExternalRefs = []ExternalRef{purlRef(component.PURL)}
		}
		document.Packages = append(document.Packages, pkg)
		document.Relationships = append(document.Relationships, Relationship{SPDXElementID: rootID, RelationshipType: "DEPENDS_ON", RelatedSPDXElement: id})
	}
	return document, nil
}

func Encode(document Document) ([]byte, error) {
	data, err := json.MarshalIndent(document, "", "  ")
	if err != nil {
		return nil, err
	}
	return append(data, '\n'), nil
}

func Write(options Options, output string) (Document, error) {
	components, err := Collect(options)
	if err != nil {
		return Document{}, err
	}
	document, err := Build(options.Version, components, options.Created)
	if err != nil {
		return Document{}, err
	}
	data, err := Encode(document)
	if err != nil {
		return Document{}, err
	}
	if directory := filepath.Dir(output); directory != "" {
		if err := os.MkdirAll(directory, 0o755); err != nil {
			return Document{}, err
		}
	}
	return document, os.WriteFile(output, data, 0o644)
}

func CreatedTime(flagValue, sourceDateEpoch string, now time.Time) (time.Time, error) {
	if flagValue != "" {
		parsed, err := time.Parse(time.RFC3339, flagValue)
		if err != nil {
			return time.Time{}, fmt.Errorf("--created must be an RFC 3339 timestamp: %w", err)
		}
		return parsed.UTC(), nil
	}
	if sourceDateEpoch != "" {
		var seconds int64
		if _, err := fmt.Sscanf(sourceDateEpoch, "%d", &seconds); err != nil {
			return time.Time{}, fmt.Errorf("SOURCE_DATE_EPOCH must be a number of seconds: %w", err)
		}
		return time.Unix(seconds, 0).UTC(), nil
	}
	return now.UTC().Truncate(time.Second), nil
}

func dedupe(components []Component) []Component {
	seen := map[string]bool{}
	unique := make([]Component, 0, len(components))
	for _, component := range components {
		key := component.Ecosystem + "|" + component.Name + "|" + component.Version
		if seen[key] {
			continue
		}
		seen[key] = true
		unique = append(unique, component)
	}
	sort.SliceStable(unique, func(left, right int) bool {
		a, b := unique[left], unique[right]
		if a.Ecosystem != b.Ecosystem {
			return a.Ecosystem < b.Ecosystem
		}
		if a.Name != b.Name {
			return a.Name < b.Name
		}
		return a.Version < b.Version
	})
	return unique
}

var invalidIDCharacters = regexp.MustCompile(`[^A-Za-z0-9.\-]+`)

func spdxID(component Component) string {
	raw := component.Ecosystem + "-" + component.Name
	if component.Version != "" {
		raw += "-" + component.Version
	}
	return "SPDXRef-Package-" + strings.Trim(invalidIDCharacters.ReplaceAllString(raw, "-"), "-")
}

func uniqueID(id string, used map[string]bool) string {
	candidate := id
	for index := 2; used[candidate]; index++ {
		candidate = fmt.Sprintf("%s-%d", id, index)
	}
	used[candidate] = true
	return candidate
}

func purlRef(locator string) ExternalRef {
	return ExternalRef{ReferenceCategory: "PACKAGE-MANAGER", ReferenceType: "purl", ReferenceLocator: locator}
}

func swiftPURL(location, name, version string) string {
	path := repositoryPath(location)
	if path == "" {
		path = name
	}
	if version == "" {
		return "pkg:swift/" + path
	}
	return "pkg:swift/" + path + "@" + version
}

func repositoryPath(location string) string {
	if location == "" {
		return ""
	}
	if strings.HasPrefix(location, "git@") {
		location = "ssh://" + strings.Replace(strings.TrimPrefix(location, "git@"), ":", "/", 1)
	}
	parsed, err := url.Parse(location)
	if err != nil || parsed.Host == "" {
		return strings.TrimSuffix(strings.Trim(location, "/"), ".git")
	}
	return strings.ToLower(parsed.Host) + "/" + strings.TrimSuffix(strings.Trim(parsed.Path, "/"), ".git")
}

func repositoryName(location string) string {
	path := repositoryPath(location)
	if path == "" {
		return ""
	}
	return path[strings.LastIndex(path, "/")+1:]
}

func downloadLocation(location string) string {
	if location == "" {
		return noAssertion
	}
	if strings.HasPrefix(location, "http://") || strings.HasPrefix(location, "https://") {
		return "git+" + location
	}
	return location
}

func escapeModulePath(path string) string {
	var builder strings.Builder
	for _, character := range path {
		if character >= 'A' && character <= 'Z' {
			builder.WriteRune('!')
			builder.WriteRune(character + ('a' - 'A'))
			continue
		}
		builder.WriteRune(character)
	}
	return builder.String()
}

func stripGoComment(line string) string {
	if index := strings.Index(line, "//"); index >= 0 {
		return line[:index]
	}
	return line
}

func firstNonEmpty(values ...string) string {
	for _, value := range values {
		if value != "" {
			return value
		}
	}
	return ""
}
