package xcstrings

import (
	"bytes"
	"os"
	"path/filepath"
	"testing"

	"github.com/itoolio/ishare/tools/internal/repo"
)

func read(t *testing.T, path string) []byte {
	t.Helper()
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	return data
}

func TestCatalogRoundTripsByteForByte(t *testing.T) {
	catalog := read(t, repo.Path("ishare", "Localizable.xcstrings"))
	merged, result, err := MergeFiles(catalog, catalog)
	if err != nil {
		t.Fatal(err)
	}
	if !bytes.Equal(merged, catalog) {
		t.Fatal("merging the catalog into itself changed its bytes")
	}
	if summary := result.Summary(); summary != "added=0\nlanguages=\n" {
		t.Fatalf("unexpected summary %q", summary)
	}
}

func TestMergeMatchesTheReferenceOutput(t *testing.T) {
	merged, result, err := MergeFiles(read(t, filepath.Join("testdata", "base.xcstrings")), read(t, filepath.Join("testdata", "incoming.xcstrings")))
	if err != nil {
		t.Fatal(err)
	}
	if want := read(t, filepath.Join("testdata", "merged.xcstrings")); !bytes.Equal(merged, want) {
		t.Fatalf("unexpected merged catalog:\n%s", merged)
	}
	if want := string(read(t, filepath.Join("testdata", "summary.txt"))); result.Summary() != want {
		t.Fatalf("unexpected summary %q, want %q", result.Summary(), want)
	}
}

func TestFormatEscapesLikePython(t *testing.T) {
	value := NewObject(Member{Key: "a\"b\\c", Value: NewString("\b\f\n\r\t\x01/<>& é")})
	want := "{\n  \"a\\\"b\\\\c\" : \"\\b\\f\\n\\r\\t\\u0001/<>& é\"\n}"
	if got := string(Format(value)); got != want {
		t.Fatalf("got %q, want %q", got, want)
	}
}

func TestFormatNumbersLikePython(t *testing.T) {
	cases := map[string]string{
		"1":       "1",
		"-12":     "-12",
		"2.50":    "2.5",
		"1e5":     "100000.0",
		"0.0001":  "0.0001",
		"0.00001": "1e-05",
		"1e16":    "1e+16",
		"1e15":    "1000000000000000.0",
		"0.0":     "0.0",
	}
	for literal, want := range cases {
		if got := formatNumber(literal); got != want {
			t.Errorf("formatNumber(%q) = %q, want %q", literal, got, want)
		}
	}
}

func TestMergeKeepsExistingTranslationsAndSortsLanguages(t *testing.T) {
	base, _ := Parse([]byte(`{"strings":{"Hi":{"localizations":{"fr":{"stringUnit":{"state":"translated","value":"Salut"}}}}}}`))
	incoming, _ := Parse([]byte(`{"strings":{"Hi":{"localizations":{"fr":{"stringUnit":{"state":"translated","value":"Bonjour"}},"de":{"stringUnit":{"state":"translated","value":"Hallo"}}}}}}`))
	result, err := Merge(base, incoming)
	if err != nil {
		t.Fatal(err)
	}
	if len(result.Additions) != 1 || result.Additions[0] != (Addition{Language: "de", Key: "Hi"}) {
		t.Fatalf("unexpected additions %+v", result.Additions)
	}
	localizations := base.Get("strings").Get("Hi").Get("localizations")
	if localizations.Members[0].Key != "de" || localizations.Members[1].Key != "fr" {
		t.Fatalf("languages are not sorted: %s", Format(localizations))
	}
	if text, _ := localizations.Get("fr").Get("stringUnit").Get("value").Text(); text != "Salut" {
		t.Fatalf("existing translation was replaced with %q", text)
	}
}

func TestMergeRejectsCatalogsWithoutStrings(t *testing.T) {
	if _, _, err := MergeFiles([]byte(`{}`), []byte(`{"strings":{}}`)); err == nil {
		t.Fatal("expected an error")
	}
	if _, _, err := MergeFiles([]byte(`{"strings":{}} {}`), []byte(`{"strings":{}}`)); err == nil {
		t.Fatal("expected trailing data to be rejected")
	}
}
