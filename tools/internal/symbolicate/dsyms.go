package symbolicate

import (
	"archive/zip"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"sort"
	"strings"
)

var RequiredDSYMs = []string{"ishare.app.dSYM", "ishareWidgets.appex.dSYM", "sharemenuext.appex.dSYM"}

type PackageResult struct {
	Bundles  []string
	Verified []string
}

func PackageArchive(runner Runner, archive, output string, required []string) (PackageResult, error) {
	directory := filepath.Join(archive, "dSYMs")
	bundles, err := FindDSYMs(directory)
	if err != nil {
		return PackageResult{}, fmt.Errorf("reading the archive's dSYMs: %w", err)
	}
	names := map[string]bool{}
	for _, bundle := range bundles {
		names[filepath.Base(bundle)] = true
	}
	var missing []string
	for _, name := range required {
		if !names[name] {
			missing = append(missing, name)
		}
	}
	if len(missing) > 0 {
		return PackageResult{}, fmt.Errorf("the archive is missing %s", strings.Join(missing, ", "))
	}
	result := PackageResult{}
	isRequired := map[string]bool{}
	for _, name := range required {
		isRequired[name] = true
	}
	for _, bundle := range bundles {
		result.Bundles = append(result.Bundles, filepath.Base(bundle))
		if !isRequired[filepath.Base(bundle)] {
			continue
		}
		binary, ok, err := ProductBinary(filepath.Join(archive, "Products"), filepath.Base(bundle))
		if err != nil {
			return PackageResult{}, err
		}
		if !ok {
			return PackageResult{}, fmt.Errorf("no binary for %s in the archive's products", filepath.Base(bundle))
		}
		if err := matchUUIDs(runner, bundle, binary); err != nil {
			return PackageResult{}, err
		}
		result.Verified = append(result.Verified, filepath.Base(bundle))
	}
	if err := os.MkdirAll(filepath.Dir(output), 0o755); err != nil {
		return PackageResult{}, err
	}
	return result, ZipDirectory(directory, "dSYMs", output)
}

func ProductBinary(products, dsymName string) (string, bool, error) {
	bundleName := strings.TrimSuffix(dsymName, ".dSYM")
	executable := strings.TrimSuffix(bundleName, filepath.Ext(bundleName))
	var found string
	err := filepath.WalkDir(products, func(path string, entry os.DirEntry, err error) error {
		if err != nil {
			if os.IsNotExist(err) {
				return filepath.SkipAll
			}
			return err
		}
		if found == "" && entry.IsDir() && entry.Name() == bundleName {
			candidate := filepath.Join(path, "Contents", "MacOS", executable)
			if info, statErr := os.Stat(candidate); statErr == nil && !info.IsDir() {
				found = candidate
				return filepath.SkipAll
			}
		}
		return nil
	})
	return found, found != "", err
}

func matchUUIDs(runner Runner, bundle, binary string) error {
	dsymOutput, err := runner.Run("dwarfdump", "--uuid", bundle)
	if err != nil {
		return err
	}
	binaryOutput, err := runner.Run("dwarfdump", "--uuid", binary)
	if err != nil {
		return err
	}
	dsymUUIDs, binaryUUIDs := uuidSet(ParseDwarfdump(dsymOutput)), uuidSet(ParseDwarfdump(binaryOutput))
	if len(binaryUUIDs) == 0 || strings.Join(dsymUUIDs, ",") != strings.Join(binaryUUIDs, ",") {
		return fmt.Errorf("%s has UUIDs %v but %s has %v", filepath.Base(bundle), dsymUUIDs, binary, binaryUUIDs)
	}
	return nil
}

func uuidSet(binaries []Binary) []string {
	uuids := make([]string, 0, len(binaries))
	for _, binary := range binaries {
		uuids = append(uuids, binary.Arch+":"+binary.UUID)
	}
	sort.Strings(uuids)
	return uuids
}

func ZipDirectory(source, prefix, output string) error {
	file, err := os.Create(output)
	if err != nil {
		return err
	}
	writer := zip.NewWriter(file)
	walkErr := filepath.WalkDir(source, func(path string, entry os.DirEntry, err error) error {
		if err != nil {
			return err
		}
		relative, err := filepath.Rel(source, path)
		if err != nil {
			return err
		}
		name := filepath.ToSlash(filepath.Join(prefix, relative))
		if entry.IsDir() {
			if relative == "." {
				return nil
			}
			_, err := writer.Create(name + "/")
			return err
		}
		if !entry.Type().IsRegular() {
			return nil
		}
		return addFile(writer, path, name)
	})
	closeErr := writer.Close()
	fileErr := file.Close()
	for _, err := range []error{walkErr, closeErr, fileErr} {
		if err != nil {
			return err
		}
	}
	return nil
}

func addFile(writer *zip.Writer, path, name string) error {
	info, err := os.Stat(path)
	if err != nil {
		return err
	}
	header, err := zip.FileInfoHeader(info)
	if err != nil {
		return err
	}
	header.Name = name
	header.Method = zip.Deflate
	destination, err := writer.CreateHeader(header)
	if err != nil {
		return err
	}
	source, err := os.Open(path)
	if err != nil {
		return err
	}
	defer source.Close()
	_, err = io.Copy(destination, source)
	return err
}
