package symbolicate

import (
	"archive/zip"
	"os"
	"path/filepath"
	"reflect"
	"sort"
	"strings"
	"testing"
)

type uuidRunner map[string]string

func (r uuidRunner) Run(name string, arguments ...string) (string, error) {
	path := arguments[len(arguments)-1]
	return "UUID: " + r[filepath.Base(path)] + " (arm64) " + path + "\n", nil
}

func makeArchive(t *testing.T, dsyms []string) string {
	t.Helper()
	archive := filepath.Join(t.TempDir(), "ishare.xcarchive")
	write := func(path string) {
		if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(path, []byte("binary"), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	app := filepath.Join(archive, "Products", "Applications", "ishare.app", "Contents")
	write(filepath.Join(app, "MacOS", "ishare"))
	write(filepath.Join(app, "PlugIns", "ishareWidgets.appex", "Contents", "MacOS", "ishareWidgets"))
	write(filepath.Join(app, "PlugIns", "sharemenuext.appex", "Contents", "MacOS", "sharemenuext"))
	for _, name := range dsyms {
		executable := strings.TrimSuffix(strings.TrimSuffix(name, ".dSYM"), filepath.Ext(strings.TrimSuffix(name, ".dSYM")))
		write(filepath.Join(archive, "dSYMs", name, "Contents", "Resources", "DWARF", executable))
	}
	return archive
}

func matchingRunner() uuidRunner {
	return uuidRunner{
		"ishare.app.dSYM": "AAAAAAAA-0000-0000-0000-000000000001", "ishare": "AAAAAAAA-0000-0000-0000-000000000001",
		"ishareWidgets.appex.dSYM": "AAAAAAAA-0000-0000-0000-000000000002", "ishareWidgets": "AAAAAAAA-0000-0000-0000-000000000002",
		"sharemenuext.appex.dSYM": "AAAAAAAA-0000-0000-0000-000000000003", "sharemenuext": "AAAAAAAA-0000-0000-0000-000000000003",
	}
}

func TestPackageArchiveZipsEveryDSYMAfterCheckingUUIDs(t *testing.T) {
	archive := makeArchive(t, append([]string{"Sparkle.framework.dSYM"}, RequiredDSYMs...))
	output := filepath.Join(t.TempDir(), "dist", "ishare-5.3.0-dSYMs.zip")
	result, err := PackageArchive(matchingRunner(), archive, output, RequiredDSYMs)
	if err != nil {
		t.Fatal(err)
	}
	wantBundles := []string{"Sparkle.framework.dSYM", "ishare.app.dSYM", "ishareWidgets.appex.dSYM", "sharemenuext.appex.dSYM"}
	if !reflect.DeepEqual(result.Bundles, wantBundles) || !reflect.DeepEqual(result.Verified, RequiredDSYMs) {
		t.Fatalf("result %+v", result)
	}
	reader, err := zip.OpenReader(output)
	if err != nil {
		t.Fatal(err)
	}
	defer reader.Close()
	var files []string
	for _, file := range reader.File {
		if !strings.HasSuffix(file.Name, "/") {
			files = append(files, file.Name)
		}
	}
	sort.Strings(files)
	want := []string{
		"dSYMs/Sparkle.framework.dSYM/Contents/Resources/DWARF/Sparkle",
		"dSYMs/ishare.app.dSYM/Contents/Resources/DWARF/ishare",
		"dSYMs/ishareWidgets.appex.dSYM/Contents/Resources/DWARF/ishareWidgets",
		"dSYMs/sharemenuext.appex.dSYM/Contents/Resources/DWARF/sharemenuext",
	}
	if !reflect.DeepEqual(files, want) {
		t.Fatalf("zip contents %v", files)
	}
}

func TestPackageArchiveFailsWhenADSYMIsMissing(t *testing.T) {
	archive := makeArchive(t, []string{"ishare.app.dSYM"})
	_, err := PackageArchive(matchingRunner(), archive, filepath.Join(t.TempDir(), "out.zip"), RequiredDSYMs)
	if err == nil || !strings.Contains(err.Error(), "ishareWidgets.appex.dSYM, sharemenuext.appex.dSYM") {
		t.Fatalf("got %v", err)
	}
}

func TestPackageArchiveFailsOnMismatchedUUIDs(t *testing.T) {
	archive := makeArchive(t, RequiredDSYMs)
	runner := matchingRunner()
	runner["ishareWidgets"] = "BBBBBBBB-0000-0000-0000-000000000002"
	_, err := PackageArchive(runner, archive, filepath.Join(t.TempDir(), "out.zip"), RequiredDSYMs)
	if err == nil || !strings.Contains(err.Error(), "ishareWidgets.appex.dSYM has UUIDs") {
		t.Fatalf("got %v", err)
	}
}

func TestProductBinaryFindsNestedExtensions(t *testing.T) {
	archive := makeArchive(t, nil)
	binary, ok, err := ProductBinary(filepath.Join(archive, "Products"), "sharemenuext.appex.dSYM")
	if err != nil || !ok || !strings.HasSuffix(binary, "PlugIns/sharemenuext.appex/Contents/MacOS/sharemenuext") {
		t.Fatalf("got %q %v %v", binary, ok, err)
	}
	if _, ok, _ := ProductBinary(filepath.Join(archive, "Products"), "Missing.app.dSYM"); ok {
		t.Fatal("a missing bundle should not be found")
	}
}
