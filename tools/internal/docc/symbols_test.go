package docc

import (
	"bytes"
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

const sample = `{
  "metadata": {"formatVersion": {"major": 0, "minor": 6, "patch": 0}},
  "module": {"name": "ishare", "platform": {}},
  "symbols": [
    {"identifier": {"precise": "s:6ishare8UploaderP"}, "pathComponents": ["Uploader"], "kind": {"identifier": "swift.protocol"}},
    {"identifier": {"precise": "s:6ishare8UploaderP6delete"}, "pathComponents": ["Uploader", "delete(_:)"]},
    {"identifier": {"precise": "s:6ishare13UploadOutcomeV"}, "pathComponents": ["UploadOutcome"]},
    {"identifier": {"precise": "s:SQ2neoiy::SYNTHESIZED::s:6ishare13UploadOutcomeV"}, "pathComponents": ["UploadOutcome", "!=(_:_:)"]},
    {"identifier": {"precise": "s:6ishare10EditorViewV"}, "pathComponents": ["EditorView"]}
  ],
  "relationships": [
    {"kind": "memberOf", "source": "s:6ishare8UploaderP6delete", "target": "s:6ishare8UploaderP"},
    {"kind": "conformsTo", "source": "s:6ishare13UploadOutcomeV", "target": "s:s8SendableP"},
    {"kind": "memberOf", "source": "s:SQ2neoiy::SYNTHESIZED::s:6ishare13UploadOutcomeV", "target": "s:6ishare13UploadOutcomeV"},
    {"kind": "conformsTo", "source": "s:6ishare10EditorViewV", "target": "s:6ishare8UploaderP"},
    {"kind": "requirementOf", "source": "s:6ishare13UploadOutcomeV", "target": "s:6ishare10EditorViewV"}
  ]
}`

type decoded struct {
	Module  map[string]any `json:"module"`
	Symbols []struct {
		Identifier struct {
			Precise string `json:"precise"`
		} `json:"identifier"`
		Kind map[string]string `json:"kind"`
	} `json:"symbols"`
	Relationships []map[string]string `json:"relationships"`
}

func TestFilterKeepsTheDocumentedTypesAndTheirMembers(t *testing.T) {
	var output bytes.Buffer
	result, err := Filter(strings.NewReader(sample), &output, []string{"Uploader", "UploadOutcome"})
	if err != nil {
		t.Fatal(err)
	}
	if result.Symbols != 3 || result.Relationships != 2 || strings.Join(result.Types, ",") != "UploadOutcome,Uploader" {
		t.Fatalf("result %+v", result)
	}
	var graph decoded
	if err := json.Unmarshal(output.Bytes(), &graph); err != nil {
		t.Fatal(err)
	}
	if graph.Module["name"] != "ishare" {
		t.Errorf("module %v", graph.Module)
	}
	var identifiers []string
	for _, symbol := range graph.Symbols {
		identifiers = append(identifiers, symbol.Identifier.Precise)
	}
	if strings.Join(identifiers, " ") != "s:6ishare8UploaderP s:6ishare8UploaderP6delete s:6ishare13UploadOutcomeV" {
		t.Errorf("symbols %v", identifiers)
	}
	if graph.Symbols[0].Kind["identifier"] != "swift.protocol" {
		t.Errorf("symbol fields were not preserved: %v", graph.Symbols[0].Kind)
	}
	if graph.Relationships[0]["kind"] != "memberOf" || graph.Relationships[1]["target"] != "s:s8SendableP" {
		t.Errorf("relationships %v", graph.Relationships)
	}
}

func TestFilterFailsWhenADocumentedTypeIsMissing(t *testing.T) {
	_, err := Filter(strings.NewReader(sample), &bytes.Buffer{}, []string{"Uploader", "Renamed"})
	if err == nil || !strings.Contains(err.Error(), "Renamed") {
		t.Fatalf("got %v", err)
	}
}

func TestFilterFileFindsTheModuleGraph(t *testing.T) {
	directory := t.TempDir()
	nested := filepath.Join(directory, "ishare.build", "symbol-graph", "swift", "arm64-apple-macos")
	if err := os.MkdirAll(nested, 0o755); err != nil {
		t.Fatal(err)
	}
	for _, name := range []string{"ishare.symbols.json", "ishare@Swift.symbols.json"} {
		if err := os.WriteFile(filepath.Join(nested, name), []byte(sample), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	output := filepath.Join(directory, "out")
	result, err := FilterFile(directory, "ishare", output, []string{"Uploader"})
	if err != nil || result.Symbols != 2 {
		t.Fatalf("result %+v, %v", result, err)
	}
	entries, _ := os.ReadDir(output)
	if len(entries) != 1 || entries[0].Name() != "ishare.symbols.json" {
		t.Fatalf("output %v", entries)
	}
	if _, err := FilterFile(directory, "missing", output, []string{"Uploader"}); err == nil {
		t.Fatal("a missing module should fail")
	}
}

func TestDocumentedTypesAreSorted(t *testing.T) {
	for index := 1; index < len(DocumentedTypes); index++ {
		if DocumentedTypes[index-1] >= DocumentedTypes[index] {
			t.Fatalf("%s should come after %s", DocumentedTypes[index-1], DocumentedTypes[index])
		}
	}
}
