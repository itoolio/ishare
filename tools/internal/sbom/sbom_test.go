package sbom

import (
	"bytes"
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

var fixedTime = time.Date(2026, 10, 25, 12, 0, 0, 0, time.UTC)

func readFixture(t *testing.T, name string) []byte {
	t.Helper()
	data, err := os.ReadFile(filepath.Join("testdata", name))
	if err != nil {
		t.Fatal(err)
	}
	return data
}

func TestParsesVersion3PackageResolved(t *testing.T) {
	components, err := ParsePackageResolved(readFixture(t, "Package.resolved.v3"))
	if err != nil {
		t.Fatal(err)
	}
	if len(components) != 3 {
		t.Fatalf("got %d components", len(components))
	}
	alamofire := components[0]
	if alamofire.Name != "alamofire" || alamofire.Version != "5.10.2" || alamofire.PURL != "pkg:swift/github.com/Alamofire/Alamofire@5.10.2" {
		t.Errorf("unexpected %+v", alamofire)
	}
	if alamofire.DownloadLocation != "git+https://github.com/Alamofire/Alamofire" {
		t.Errorf("download location %q", alamofire.DownloadLocation)
	}
	if components[1].PURL != "pkg:swift/github.com/orlandos-nl/Citadel@0.12.0" {
		t.Errorf("the .git suffix was kept: %q", components[1].PURL)
	}
	branch := components[2]
	if branch.Version != "af76cf3ef710b6ca5f8c05f3a31307d44a3c5828" || !strings.HasSuffix(branch.PURL, "@af76cf3ef710b6ca5f8c05f3a31307d44a3c5828") {
		t.Errorf("a branch pin should fall back to its revision: %+v", branch)
	}
}

func TestParsesVersion2PackageResolvedWithSSHLocations(t *testing.T) {
	components, err := ParsePackageResolved(readFixture(t, "Package.resolved.v2"))
	if err != nil {
		t.Fatal(err)
	}
	if len(components) != 2 || components[0].PURL != "pkg:swift/github.com/sparkle-project/Sparkle@2.6.4" {
		t.Fatalf("unexpected %+v", components)
	}
	if components[0].DownloadLocation != "git@github.com:sparkle-project/Sparkle.git" {
		t.Errorf("download location %q", components[0].DownloadLocation)
	}
}

func TestParsesVersion1PackageResolved(t *testing.T) {
	components, err := ParsePackageResolved(readFixture(t, "Package.resolved.v1"))
	if err != nil {
		t.Fatal(err)
	}
	if len(components) != 1 || components[0].Name != "defaults" || components[0].PURL != "pkg:swift/github.com/sindresorhus/Defaults@9.0.3" {
		t.Fatalf("unexpected %+v", components)
	}
}

func TestRejectsMalformedPackageResolved(t *testing.T) {
	if _, err := ParsePackageResolved([]byte("{")); err == nil {
		t.Fatal("expected an error")
	}
}

func TestParsesGoModRequirementsIncludingIndirectOnes(t *testing.T) {
	data := readFixture(t, "go.mod.txt")
	components, err := ParseGoMod(data)
	if err != nil {
		t.Fatal(err)
	}
	var purls []string
	for _, component := range components {
		purls = append(purls, component.PURL)
	}
	want := "pkg:golang/github.com/BurntSushi/toml@v1.4.0 pkg:golang/golang.org/x/sync@v0.10.0 pkg:golang/golang.org/x/text@v0.21.0"
	if strings.Join(purls, " ") != want {
		t.Fatalf("got %v", purls)
	}
	if components[0].DownloadLocation != "https://proxy.golang.org/github.com/!burnt!sushi/toml/@v/v1.4.0.zip" {
		t.Errorf("download location %q", components[0].DownloadLocation)
	}
	module, err := ParseGoModule(data)
	if err != nil || module != "github.com/itoolio/ishare/tools" {
		t.Fatalf("module %q, %v", module, err)
	}
}

func TestParsesGoModWithoutRequirements(t *testing.T) {
	components, err := ParseGoMod([]byte("module example.com/tools\n\ngo 1.24\n"))
	if err != nil || len(components) != 0 {
		t.Fatalf("got %v, %v", components, err)
	}
}

func TestRejectsUnterminatedRequireBlock(t *testing.T) {
	if _, err := ParseGoMod([]byte("module m\nrequire (\n\ta v1\n")); err == nil {
		t.Fatal("expected an error")
	}
}

func TestReadsTheLocalPackageName(t *testing.T) {
	component, err := ParseLocalPackage(filepath.Join("testdata", "localpkg"), "5.5.0")
	if err != nil {
		t.Fatal(err)
	}
	if component.Name != "ishareCore" || component.PURL != "pkg:swift/github.com/itoolio/ishare@v5.5.0#testdata/localpkg" {
		t.Fatalf("unexpected %+v", component)
	}
}

func testOptions() Options {
	return Options{
		Version:         "5.5.0",
		PackageResolved: []string{filepath.Join("testdata", "Package.resolved.v3"), filepath.Join("testdata", "Package.resolved.v2")},
		PackageDirs:     []string{filepath.Join("testdata", "localpkg")},
		GoModules:       []string{filepath.Join("testdata", "go.mod.txt")},
		Created:         fixedTime,
	}
}

func TestBuildsADeterministicSPDXDocument(t *testing.T) {
	components, err := Collect(testOptions())
	if err != nil {
		t.Fatal(err)
	}
	document, err := Build("5.5.0", components, fixedTime)
	if err != nil {
		t.Fatal(err)
	}
	if document.SPDXVersion != "SPDX-2.3" || document.DataLicense != "CC0-1.0" || document.CreationInfo.Created != "2026-10-25T12:00:00Z" {
		t.Errorf("unexpected header %+v", document)
	}
	if document.DocumentNamespace != "https://github.com/itoolio/ishare/releases/download/v5.5.0/ishare-5.5.0-sbom.spdx.json" {
		t.Errorf("namespace %q", document.DocumentNamespace)
	}
	if len(document.Packages) != 1+4+1+1+3 {
		t.Fatalf("got %d packages, alamofire should be deduplicated", len(document.Packages))
	}
	root := document.Packages[0]
	if root.SPDXID != "SPDXRef-Package-ishare" || root.VersionInfo != "5.5.0" || root.ExternalRefs[0].ReferenceLocator != "pkg:github/itoolio/ishare@v5.5.0" {
		t.Errorf("unexpected root %+v", root)
	}
	ids := map[string]bool{}
	for _, pkg := range document.Packages {
		if ids[pkg.SPDXID] {
			t.Errorf("duplicate SPDXID %s", pkg.SPDXID)
		}
		ids[pkg.SPDXID] = true
	}
	describes, dependsOn := 0, 0
	for _, relationship := range document.Relationships {
		switch relationship.RelationshipType {
		case "DESCRIBES":
			describes++
			if relationship.SPDXElementID != "SPDXRef-DOCUMENT" || relationship.RelatedSPDXElement != root.SPDXID {
				t.Errorf("unexpected %+v", relationship)
			}
		case "DEPENDS_ON":
			dependsOn++
			if relationship.SPDXElementID != root.SPDXID || !ids[relationship.RelatedSPDXElement] {
				t.Errorf("unexpected %+v", relationship)
			}
		}
	}
	if describes != 1 || dependsOn != len(document.Packages)-1 {
		t.Errorf("%d DESCRIBES and %d DEPENDS_ON relationships", describes, dependsOn)
	}
	if document.Packages[1].SPDXID != "SPDXRef-Package-go-github.com-BurntSushi-toml-v1.4.0" {
		t.Errorf("packages are not sorted by ecosystem and name: %s", document.Packages[1].SPDXID)
	}
}

func TestWritesIdenticalOutputTwice(t *testing.T) {
	directory := t.TempDir()
	first := filepath.Join(directory, "a", "sbom.json")
	second := filepath.Join(directory, "b", "sbom.json")
	if _, err := Write(testOptions(), first); err != nil {
		t.Fatal(err)
	}
	if _, err := Write(testOptions(), second); err != nil {
		t.Fatal(err)
	}
	a, _ := os.ReadFile(first)
	b, _ := os.ReadFile(second)
	if !bytes.Equal(a, b) {
		t.Fatal("the SBOM is not deterministic")
	}
	var decoded map[string]any
	if err := json.Unmarshal(a, &decoded); err != nil {
		t.Fatal(err)
	}
	if decoded["SPDXID"] != "SPDXRef-DOCUMENT" {
		t.Errorf("unexpected %v", decoded["SPDXID"])
	}
}

func TestBuildRequiresAVersion(t *testing.T) {
	if _, err := Build("", nil, fixedTime); err == nil {
		t.Fatal("expected an error")
	}
}

func TestCreatedTimePrefersTheFlagThenSourceDateEpoch(t *testing.T) {
	now := time.Date(2030, 1, 1, 0, 0, 0, 500, time.UTC)
	if created, err := CreatedTime("2026-01-02T03:04:05Z", "100", now); err != nil || !created.Equal(time.Date(2026, 1, 2, 3, 4, 5, 0, time.UTC)) {
		t.Errorf("flag: %v %v", created, err)
	}
	if created, err := CreatedTime("", "100", now); err != nil || created.Unix() != 100 {
		t.Errorf("epoch: %v %v", created, err)
	}
	if created, err := CreatedTime("", "", now); err != nil || !created.Equal(now.Truncate(time.Second)) {
		t.Errorf("now: %v %v", created, err)
	}
	if _, err := CreatedTime("yesterday", "", now); err == nil {
		t.Error("expected an error for a malformed flag")
	}
	if _, err := CreatedTime("", "soon", now); err == nil {
		t.Error("expected an error for a malformed epoch")
	}
}

func TestSPDXIDsOnlyUseAllowedCharacters(t *testing.T) {
	id := spdxID(Component{Ecosystem: "swift", Name: "a_b/c@d", Version: "1.0+meta"})
	if id != "SPDXRef-Package-swift-a-b-c-d-1.0-meta" {
		t.Fatalf("got %q", id)
	}
	used := map[string]bool{"x": true}
	if uniqueID("x", used) != "x-2" {
		t.Fatal("collisions should get a suffix")
	}
}
