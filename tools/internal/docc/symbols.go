package docc

import (
	"encoding/json"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"sort"
	"strings"
)

var DocumentedTypes = []string{
	"CustomUploader",
	"DeleteRequestType",
	"FolderDestination",
	"FolderUploader",
	"HTTPUploader",
	"HistoryItem",
	"ImgurUploader",
	"LinkOptionsSpec",
	"PhotosDestination",
	"PhotosUploader",
	"RequestBodyType",
	"ResponseTemplate",
	"S3Configuration",
	"S3Uploader",
	"UploadCoordinator",
	"UploadEnvironment",
	"UploadFailure",
	"UploadOutcome",
	"UploadRequestMethod",
	"UploadService",
	"UploadTarget",
	"Uploader",
	"UploaderIssue",
	"UploaderKind",
	"UploaderValidator",
}

type graph struct {
	Metadata      json.RawMessage   `json:"metadata"`
	Module        json.RawMessage   `json:"module"`
	Symbols       []json.RawMessage `json:"symbols"`
	Relationships []relationship    `json:"relationships"`
}

type relationship struct {
	Source string `json:"source"`
	Target string `json:"target"`
	Raw    json.RawMessage
}

func (r *relationship) UnmarshalJSON(data []byte) error {
	var fields struct {
		Source string `json:"source"`
		Target string `json:"target"`
	}
	if err := json.Unmarshal(data, &fields); err != nil {
		return err
	}
	r.Source, r.Target, r.Raw = fields.Source, fields.Target, append(json.RawMessage{}, data...)
	return nil
}

func (r relationship) MarshalJSON() ([]byte, error) {
	return r.Raw, nil
}

type symbolHeader struct {
	Identifier struct {
		Precise string `json:"precise"`
	} `json:"identifier"`
	PathComponents []string `json:"pathComponents"`
}

type Result struct {
	Symbols       int
	Relationships int
	Types         []string
}

func Filter(input io.Reader, output io.Writer, types []string) (Result, error) {
	var source graph
	if err := json.NewDecoder(input).Decode(&source); err != nil {
		return Result{}, fmt.Errorf("reading the symbol graph: %w", err)
	}
	wanted := map[string]bool{}
	for _, name := range types {
		wanted[name] = true
	}
	all := map[string]bool{}
	kept := map[string]bool{}
	found := map[string]bool{}
	filtered := graph{Metadata: source.Metadata, Module: source.Module, Symbols: []json.RawMessage{}, Relationships: []relationship{}}
	for _, raw := range source.Symbols {
		var header symbolHeader
		if err := json.Unmarshal(raw, &header); err != nil {
			return Result{}, fmt.Errorf("reading a symbol: %w", err)
		}
		precise := header.Identifier.Precise
		all[precise] = true
		if strings.Contains(precise, "::SYNTHESIZED::") || len(header.PathComponents) == 0 || !wanted[header.PathComponents[0]] {
			continue
		}
		kept[precise] = true
		found[header.PathComponents[0]] = true
		filtered.Symbols = append(filtered.Symbols, raw)
	}
	for _, relation := range source.Relationships {
		if kept[relation.Source] && (kept[relation.Target] || !all[relation.Target]) {
			filtered.Relationships = append(filtered.Relationships, relation)
		}
	}
	var missing []string
	for _, name := range types {
		if !found[name] {
			missing = append(missing, name)
		}
	}
	if len(missing) > 0 {
		return Result{}, fmt.Errorf("the symbol graph has no %s", strings.Join(missing, ", "))
	}
	encoder := json.NewEncoder(output)
	if err := encoder.Encode(filtered); err != nil {
		return Result{}, err
	}
	names := make([]string, 0, len(found))
	for name := range found {
		names = append(names, name)
	}
	sort.Strings(names)
	return Result{Symbols: len(filtered.Symbols), Relationships: len(filtered.Relationships), Types: names}, nil
}

func FindModuleGraph(directory, module string) (string, error) {
	var found string
	err := filepath.WalkDir(directory, func(path string, entry os.DirEntry, err error) error {
		if err != nil {
			return err
		}
		if found == "" && !entry.IsDir() && entry.Name() == module+".symbols.json" {
			found = path
			return filepath.SkipAll
		}
		return nil
	})
	if err != nil {
		return "", err
	}
	if found == "" {
		return "", fmt.Errorf("no %s.symbols.json in %s", module, directory)
	}
	return found, nil
}

func FilterFile(directory, module, outputDirectory string, types []string) (Result, error) {
	path, err := FindModuleGraph(directory, module)
	if err != nil {
		return Result{}, err
	}
	input, err := os.Open(path)
	if err != nil {
		return Result{}, err
	}
	defer input.Close()
	if err := os.MkdirAll(outputDirectory, 0o755); err != nil {
		return Result{}, err
	}
	output, err := os.Create(filepath.Join(outputDirectory, module+".symbols.json"))
	if err != nil {
		return Result{}, err
	}
	result, err := Filter(input, output, types)
	if closeErr := output.Close(); err == nil {
		err = closeErr
	}
	return result, err
}
