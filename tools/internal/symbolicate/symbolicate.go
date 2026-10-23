package symbolicate

import (
	"archive/zip"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
)

type Runner interface {
	Run(name string, arguments ...string) (string, error)
}

type ExecRunner struct{}

func (ExecRunner) Run(name string, arguments ...string) (string, error) {
	output, err := exec.Command(name, arguments...).Output()
	if err != nil {
		return "", fmt.Errorf("%s failed: %w", name, err)
	}
	return string(output), nil
}

var dwarfdumpLine = regexp.MustCompile(`UUID:\s+([0-9A-Fa-f-]{32,36})\s+\(([^)]+)\)\s+(.+)$`)

type Binary struct {
	UUID string
	Arch string
	Path string
}

func ParseDwarfdump(output string) []Binary {
	var binaries []Binary
	for _, line := range strings.Split(output, "\n") {
		match := dwarfdumpLine.FindStringSubmatch(strings.TrimSpace(line))
		if match == nil {
			continue
		}
		binaries = append(binaries, Binary{UUID: NormalizeUUID(match[1]), Arch: match[2], Path: strings.TrimSpace(match[3])})
	}
	return binaries
}

func FindDSYMs(root string) ([]string, error) {
	var bundles []string
	err := filepath.WalkDir(root, func(path string, entry os.DirEntry, err error) error {
		if err != nil {
			return err
		}
		if entry.IsDir() && strings.HasSuffix(entry.Name(), ".dSYM") {
			bundles = append(bundles, path)
			return filepath.SkipDir
		}
		return nil
	})
	sort.Strings(bundles)
	return bundles, err
}

func Unzip(archive, destination string) error {
	reader, err := zip.OpenReader(archive)
	if err != nil {
		return err
	}
	defer reader.Close()
	for _, file := range reader.File {
		target := filepath.Join(destination, file.Name)
		if !strings.HasPrefix(target, filepath.Clean(destination)+string(os.PathSeparator)) {
			return fmt.Errorf("%s escapes the extraction directory", file.Name)
		}
		if file.FileInfo().IsDir() {
			if err := os.MkdirAll(target, 0o755); err != nil {
				return err
			}
			continue
		}
		if file.Mode()&os.ModeSymlink != 0 {
			continue
		}
		if err := extract(file, target); err != nil {
			return err
		}
	}
	return nil
}

func extract(file *zip.File, target string) error {
	if err := os.MkdirAll(filepath.Dir(target), 0o755); err != nil {
		return err
	}
	source, err := file.Open()
	if err != nil {
		return err
	}
	defer source.Close()
	output, err := os.OpenFile(target, os.O_CREATE|os.O_TRUNC|os.O_WRONLY, 0o644)
	if err != nil {
		return err
	}
	if _, err := io.Copy(output, source); err != nil {
		output.Close()
		return err
	}
	return output.Close()
}

func IndexBinaries(runner Runner, bundles []string) (map[string]Binary, error) {
	index := map[string]Binary{}
	for _, bundle := range bundles {
		output, err := runner.Run("dwarfdump", "--uuid", bundle)
		if err != nil {
			return nil, err
		}
		for _, binary := range ParseDwarfdump(output) {
			index[binary.UUID] = binary
		}
	}
	return index, nil
}

type Lookup struct {
	ImageIndex int
	Binary     Binary
	Base       uint64
	Addresses  []uint64
}

func PlanLookups(report Report, binaries map[string]Binary) []Lookup {
	byImage := map[int]*Lookup{}
	seen := map[int]map[uint64]bool{}
	for _, thread := range report.Threads {
		for _, frame := range thread.Frames {
			if frame.ImageIndex < 0 || frame.ImageIndex >= len(report.Images) {
				continue
			}
			image := report.Images[frame.ImageIndex]
			binary, ok := binaries[image.UUID]
			if !ok {
				continue
			}
			lookup, exists := byImage[frame.ImageIndex]
			if !exists {
				lookup = &Lookup{ImageIndex: frame.ImageIndex, Binary: binary, Base: image.Base}
				byImage[frame.ImageIndex] = lookup
				seen[frame.ImageIndex] = map[uint64]bool{}
			}
			if !seen[frame.ImageIndex][frame.Address] {
				seen[frame.ImageIndex][frame.Address] = true
				lookup.Addresses = append(lookup.Addresses, frame.Address)
			}
		}
	}
	lookups := make([]Lookup, 0, len(byImage))
	for _, lookup := range byImage {
		lookups = append(lookups, *lookup)
	}
	sort.Slice(lookups, func(i, j int) bool { return lookups[i].ImageIndex < lookups[j].ImageIndex })
	return lookups
}

func AtosArguments(lookup Lookup, arch string) []string {
	if arch == "" {
		arch = lookup.Binary.Arch
	}
	arguments := []string{"-arch", arch, "-o", lookup.Binary.Path, "-l", hex(lookup.Base)}
	for _, address := range lookup.Addresses {
		arguments = append(arguments, hex(address))
	}
	return arguments
}

func ParseAtos(output string, addresses []uint64) map[uint64]string {
	symbols := map[uint64]string{}
	lines := strings.Split(strings.TrimRight(output, "\n"), "\n")
	for index, address := range addresses {
		if index >= len(lines) {
			break
		}
		symbol := strings.TrimSpace(lines[index])
		if symbol != "" && !strings.HasPrefix(symbol, "0x") {
			symbols[address] = symbol
		}
	}
	return symbols
}

func Symbolicate(report Report, runner Runner, binaries map[string]Binary) (Report, int, error) {
	resolved := 0
	symbols := map[int]map[uint64]string{}
	for _, lookup := range PlanLookups(report, binaries) {
		arch := report.Images[lookup.ImageIndex].Arch
		output, err := runner.Run("atos", AtosArguments(lookup, arch)...)
		if err != nil {
			return report, 0, err
		}
		symbols[lookup.ImageIndex] = ParseAtos(output, lookup.Addresses)
	}
	threads := make([]Thread, len(report.Threads))
	for threadIndex, thread := range report.Threads {
		frames := make([]Frame, len(thread.Frames))
		for frameIndex, frame := range thread.Frames {
			if symbol, ok := symbols[frame.ImageIndex][frame.Address]; ok {
				frame.Symbol = symbol
				resolved++
			}
			frames[frameIndex] = frame
		}
		thread.Frames = frames
		threads[threadIndex] = thread
	}
	report.Threads = threads
	return report, resolved, nil
}

func Render(report Report) string {
	var builder strings.Builder
	if report.AppName != "" {
		fmt.Fprintf(&builder, "Process: %s\n", report.AppName)
	}
	if report.Version != "" {
		fmt.Fprintf(&builder, "Version: %s\n", report.Version)
	}
	for _, thread := range report.Threads {
		fmt.Fprintf(&builder, "\n%s:\n", thread.Name)
		for _, frame := range thread.Frames {
			name := "???"
			if frame.ImageIndex >= 0 && frame.ImageIndex < len(report.Images) && report.Images[frame.ImageIndex].Name != "" {
				name = report.Images[frame.ImageIndex].Name
			}
			symbol := frame.Symbol
			if symbol == "" {
				symbol = "???"
			}
			fmt.Fprintf(&builder, "%-3d %-30s %s %s\n", frame.Index, name, hex(frame.Address), symbol)
		}
	}
	return builder.String()
}

func hex(value uint64) string {
	return fmt.Sprintf("0x%x", value)
}
