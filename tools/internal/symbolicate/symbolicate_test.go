package symbolicate

import (
	"archive/zip"
	"fmt"
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"testing"
)

const appUUID = "1C2D3E4F5A6B7C8D9E0F1A2B3C4D5E6F"

func readFixture(t *testing.T, name string) Report {
	t.Helper()
	data, err := os.ReadFile(filepath.Join("testdata", name))
	if err != nil {
		t.Fatal(err)
	}
	report, err := Parse(data)
	if err != nil {
		t.Fatal(err)
	}
	return report
}

func TestNormalizeUUID(t *testing.T) {
	if got := NormalizeUUID(" 1c2d3e4f-5a6b-7c8d-9e0f-1a2b3c4d5e6f "); got != appUUID {
		t.Fatalf("got %q", got)
	}
}

func TestParseIPS(t *testing.T) {
	report := readFixture(t, "ishare.ips")
	if report.AppName != "ishare" || report.Version != "5.3.0 (412)" {
		t.Fatalf("header %q %q", report.AppName, report.Version)
	}
	if len(report.Images) != 4 || report.Images[0].UUID != appUUID || report.Images[0].Base != 0x1024a0000 {
		t.Fatalf("images %+v", report.Images)
	}
	if len(report.Threads) != 2 {
		t.Fatalf("threads %+v", report.Threads)
	}
	crashed := report.Threads[0]
	if !crashed.Triggered || crashed.Name != "Thread 0 com.apple.main-thread Crashed" {
		t.Fatalf("crashed thread %+v", crashed)
	}
	if crashed.Frames[0].Address != 0x1024a1234 || crashed.Frames[1].Address != 0x1024a2000 {
		t.Fatalf("addresses %x %x", crashed.Frames[0].Address, crashed.Frames[1].Address)
	}
	if crashed.Frames[2].Symbol != "specialized UploadWidget.render() + 16" {
		t.Fatalf("symbol %q", crashed.Frames[2].Symbol)
	}
	if report.Threads[1].Name != "Thread 1 com.apple.uikit.eventfetch-thread" {
		t.Fatalf("second thread %q", report.Threads[1].Name)
	}
}

func TestParseIPSIncludesTheLastExceptionBacktrace(t *testing.T) {
	data := `{"app_name":"ishare","app_version":"1.0"}
{"usedImages":[{"uuid":"` + appUUID + `","base":4096,"name":"ishare","arch":"arm64"}],"lastExceptionBacktrace":[{"imageOffset":16,"imageIndex":0}],"threads":[]}`
	report, err := Parse([]byte(data))
	if err != nil {
		t.Fatal(err)
	}
	if len(report.Threads) != 1 || report.Threads[0].Name != "Last Exception Backtrace" || report.Threads[0].Frames[0].Address != 4112 {
		t.Fatalf("got %+v", report.Threads)
	}
}

func TestParseIPSRejectsGarbage(t *testing.T) {
	if _, err := Parse([]byte(`{"app_name":"ishare"} not json`)); err == nil {
		t.Fatal("expected an error")
	}
}

func TestParseCrash(t *testing.T) {
	report := readFixture(t, "ishare.crash")
	if report.AppName != "ishare" || report.Version != "5.3.0 (412)" {
		t.Fatalf("header %q %q", report.AppName, report.Version)
	}
	wantImages := []Image{
		{Name: "ishare", UUID: appUUID, Base: 0x1024a0000, End: 0x10259ffff, Arch: "arm64", Path: "/Applications/ishare.app/Contents/MacOS/ishare"},
		{Name: "libsystem_kernel.dylib", UUID: "11111111222233334444555555555555", Base: 0x188000000, End: 0x18803bfff, Arch: "arm64e", Path: "/usr/lib/system/libsystem_kernel.dylib"},
	}
	if !reflect.DeepEqual(report.Images, wantImages) {
		t.Fatalf("images %+v", report.Images)
	}
	if len(report.Threads) != 2 || !report.Threads[0].Triggered || report.Threads[1].Triggered {
		t.Fatalf("threads %+v", report.Threads)
	}
	frames := report.Threads[0].Frames
	if len(frames) != 3 || frames[0].ImageIndex != 0 || frames[2].ImageIndex != 1 || frames[2].Symbol != "__pthread_kill + 8" {
		t.Fatalf("frames %+v", frames)
	}
	if frames[1].Address != 0x1024a2000 {
		t.Fatalf("address %x", frames[1].Address)
	}
}

func TestParseCrashWithBundleIdentifierImages(t *testing.T) {
	data := "Thread 0 Crashed:\n0   ishare   0x0000000100004010 0x100000000 + 16400\n\nBinary Images:\n       0x100000000 -        0x100ffffff dev.adrian.ishare (5.3.0) <" + appUUID + "> /Applications/ishare.app/Contents/MacOS/ishare\n"
	report, err := Parse([]byte(data))
	if err != nil {
		t.Fatal(err)
	}
	if report.Images[0].Name != "dev.adrian.ishare" || report.Images[0].UUID != appUUID || report.Threads[0].Frames[0].ImageIndex != 0 {
		t.Fatalf("got %+v", report)
	}
}

func TestParseCrashNeedsThreads(t *testing.T) {
	if _, err := Parse([]byte("Process: ishare\n")); err == nil {
		t.Fatal("expected an error")
	}
}

func TestParseDwarfdump(t *testing.T) {
	output := "UUID: 1C2D3E4F-5A6B-7C8D-9E0F-1A2B3C4D5E6F (arm64) /tmp/dsyms/ishare.app.dSYM/Contents/Resources/DWARF/ishare\n" +
		"UUID: AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE (arm64) /tmp/dsyms/My Widgets.appex.dSYM/Contents/Resources/DWARF/My Widgets\n" +
		"warning: something irrelevant\n"
	got := ParseDwarfdump(output)
	want := []Binary{
		{UUID: appUUID, Arch: "arm64", Path: "/tmp/dsyms/ishare.app.dSYM/Contents/Resources/DWARF/ishare"},
		{UUID: "AAAAAAAABBBBCCCCDDDDEEEEEEEEEEEE", Arch: "arm64", Path: "/tmp/dsyms/My Widgets.appex.dSYM/Contents/Resources/DWARF/My Widgets"},
	}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("got %+v", got)
	}
}

func TestPlanLookupsGroupsUniqueAddressesPerImageWithADSYM(t *testing.T) {
	report := readFixture(t, "ishare.ips")
	binaries := map[string]Binary{appUUID: {UUID: appUUID, Arch: "arm64", Path: "/dsyms/ishare"}}
	lookups := PlanLookups(report, binaries)
	if len(lookups) != 1 {
		t.Fatalf("lookups %+v", lookups)
	}
	if !reflect.DeepEqual(lookups[0].Addresses, []uint64{0x1024a1234, 0x1024a2000}) || lookups[0].Base != 0x1024a0000 {
		t.Fatalf("lookup %+v", lookups[0])
	}
	want := []string{"-arch", "arm64", "-o", "/dsyms/ishare", "-l", "0x1024a0000", "0x1024a1234", "0x1024a2000"}
	if got := AtosArguments(lookups[0], "arm64"); !reflect.DeepEqual(got, want) {
		t.Fatalf("atos arguments %v", got)
	}
}

func TestParseAtosSkipsUnresolvedAddresses(t *testing.T) {
	addresses := []uint64{1, 2, 3}
	got := ParseAtos("UploadService.upload(fileURL:) (in ishare) (UploadService.swift:12)\n0x2 (in ishare)\n\n", addresses)
	want := map[uint64]string{1: "UploadService.upload(fileURL:) (in ishare) (UploadService.swift:12)"}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("got %v", got)
	}
}

type fakeRunner struct {
	calls   [][]string
	outputs map[string]string
}

func (f *fakeRunner) Run(name string, arguments ...string) (string, error) {
	f.calls = append(f.calls, append([]string{name}, arguments...))
	output, ok := f.outputs[name]
	if !ok {
		return "", fmt.Errorf("unexpected %s", name)
	}
	return output, nil
}

func TestSymbolicateReplacesResolvedFrames(t *testing.T) {
	report := readFixture(t, "ishare.ips")
	runner := &fakeRunner{outputs: map[string]string{
		"dwarfdump": "UUID: 1C2D3E4F-5A6B-7C8D-9E0F-1A2B3C4D5E6F (arm64) /dsyms/ishare.app.dSYM/Contents/Resources/DWARF/ishare\n",
		"atos":      "CaptureSession.captureImage(_:) (in ishare) (CaptureSession.swift:27)\nAppState.init() (in ishare) (AppState.swift:14)\n",
	}}
	binaries, err := IndexBinaries(runner, []string{"/dsyms/ishare.app.dSYM"})
	if err != nil {
		t.Fatal(err)
	}
	symbolicated, resolved, err := Symbolicate(report, runner, binaries)
	if err != nil {
		t.Fatal(err)
	}
	if resolved != 3 {
		t.Fatalf("resolved %d frames", resolved)
	}
	if len(runner.calls) != 2 || runner.calls[1][0] != "atos" {
		t.Fatalf("calls %v", runner.calls)
	}
	rendered := Render(symbolicated)
	for _, want := range []string{
		"Process: ishare",
		"Thread 0 com.apple.main-thread Crashed:",
		"0   ishare                         0x1024a1234 CaptureSession.captureImage(_:) (in ishare) (CaptureSession.swift:27)",
		"1   ishare                         0x1024a2000 AppState.init() (in ishare) (AppState.swift:14)",
		"2   ishareWidgets                  0x102ca0800 specialized UploadWidget.render() + 16",
		"3   libsystem_kernel.dylib         0x18801869f __pthread_kill + 8",
		"1   ???                            0x200 ???",
	} {
		if !strings.Contains(rendered, want) {
			t.Errorf("rendered output is missing %q:\n%s", want, rendered)
		}
	}
	if report.Threads[0].Frames[0].Symbol != "" {
		t.Errorf("the original report should be left untouched")
	}
}

func TestFindDSYMsAndUnzip(t *testing.T) {
	directory := t.TempDir()
	archive := filepath.Join(directory, "ishare-5.3.0-dSYMs.zip")
	file, err := os.Create(archive)
	if err != nil {
		t.Fatal(err)
	}
	writer := zip.NewWriter(file)
	for _, name := range []string{
		"dSYMs/ishare.app.dSYM/Contents/Info.plist",
		"dSYMs/ishare.app.dSYM/Contents/Resources/DWARF/ishare",
		"dSYMs/ishareWidgets.appex.dSYM/Contents/Resources/DWARF/ishareWidgets",
	} {
		entry, err := writer.Create(name)
		if err != nil {
			t.Fatal(err)
		}
		entry.Write([]byte("dwarf"))
	}
	writer.Close()
	file.Close()

	extracted := filepath.Join(directory, "out")
	if err := Unzip(archive, extracted); err != nil {
		t.Fatal(err)
	}
	bundles, err := FindDSYMs(extracted)
	if err != nil {
		t.Fatal(err)
	}
	want := []string{
		filepath.Join(extracted, "dSYMs", "ishare.app.dSYM"),
		filepath.Join(extracted, "dSYMs", "ishareWidgets.appex.dSYM"),
	}
	if !reflect.DeepEqual(bundles, want) {
		t.Fatalf("bundles %v", bundles)
	}
}

func TestUnzipRejectsPathTraversal(t *testing.T) {
	directory := t.TempDir()
	archive := filepath.Join(directory, "evil.zip")
	file, _ := os.Create(archive)
	writer := zip.NewWriter(file)
	entry, _ := writer.Create("../escape.txt")
	entry.Write([]byte("x"))
	writer.Close()
	file.Close()
	if err := Unzip(archive, filepath.Join(directory, "out")); err == nil {
		t.Fatal("expected the traversal to be rejected")
	}
}
