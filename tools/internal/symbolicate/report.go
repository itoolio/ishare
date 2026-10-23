package symbolicate

import (
	"bufio"
	"bytes"
	"encoding/json"
	"fmt"
	"regexp"
	"strconv"
	"strings"
)

type Image struct {
	Name string
	UUID string
	Base uint64
	End  uint64
	Arch string
	Path string
}

type Frame struct {
	Index      int
	ImageIndex int
	Address    uint64
	Symbol     string
}

type Thread struct {
	Name      string
	Triggered bool
	Frames    []Frame
}

type Report struct {
	AppName string
	Version string
	Images  []Image
	Threads []Thread
}

func NormalizeUUID(value string) string {
	return strings.ToUpper(strings.ReplaceAll(strings.TrimSpace(value), "-", ""))
}

func Parse(data []byte) (Report, error) {
	trimmed := bytes.TrimSpace(data)
	if len(trimmed) > 0 && trimmed[0] == '{' {
		return ParseIPS(trimmed)
	}
	return ParseCrash(trimmed)
}

type ipsHeader struct {
	AppName    string `json:"app_name"`
	AppVersion string `json:"app_version"`
	BuildVer   string `json:"build_version"`
}

type ipsImage struct {
	UUID string `json:"uuid"`
	Base uint64 `json:"base"`
	Name string `json:"name"`
	Arch string `json:"arch"`
	Path string `json:"path"`
}

type ipsFrame struct {
	ImageOffset uint64 `json:"imageOffset"`
	ImageIndex  int    `json:"imageIndex"`
	Symbol      string `json:"symbol"`
	Location    uint64 `json:"symbolLocation"`
}

type ipsThread struct {
	Name      string     `json:"name"`
	Queue     string     `json:"queue"`
	Triggered bool       `json:"triggered"`
	Frames    []ipsFrame `json:"frames"`
}

type ipsBody struct {
	ProcName               string      `json:"procName"`
	UsedImages             []ipsImage  `json:"usedImages"`
	Threads                []ipsThread `json:"threads"`
	LastExceptionBacktrace []ipsFrame  `json:"lastExceptionBacktrace"`
}

func ParseIPS(data []byte) (Report, error) {
	decoder := json.NewDecoder(bytes.NewReader(data))
	var header ipsHeader
	if err := decoder.Decode(&header); err != nil {
		return Report{}, fmt.Errorf("reading the .ips header: %w", err)
	}
	var body ipsBody
	if err := decoder.Decode(&body); err != nil {
		return Report{}, fmt.Errorf("reading the .ips body: %w", err)
	}
	report := Report{AppName: header.AppName, Version: strings.TrimSpace(header.AppVersion + " " + parenthesized(header.BuildVer))}
	if report.AppName == "" {
		report.AppName = body.ProcName
	}
	for _, image := range body.UsedImages {
		report.Images = append(report.Images, Image{Name: image.Name, UUID: NormalizeUUID(image.UUID), Base: image.Base, Arch: image.Arch, Path: image.Path})
	}
	if len(body.LastExceptionBacktrace) > 0 {
		report.Threads = append(report.Threads, Thread{Name: "Last Exception Backtrace", Frames: ipsFrames(body.LastExceptionBacktrace, report.Images)})
	}
	for index, thread := range body.Threads {
		name := fmt.Sprintf("Thread %d", index)
		if label := firstNonEmpty(thread.Name, thread.Queue); label != "" {
			name += " " + label
		}
		if thread.Triggered {
			name += " Crashed"
		}
		report.Threads = append(report.Threads, Thread{Name: name, Triggered: thread.Triggered, Frames: ipsFrames(thread.Frames, report.Images)})
	}
	return report, nil
}

func ipsFrames(frames []ipsFrame, images []Image) []Frame {
	result := make([]Frame, 0, len(frames))
	for index, frame := range frames {
		var base uint64
		if frame.ImageIndex >= 0 && frame.ImageIndex < len(images) {
			base = images[frame.ImageIndex].Base
		}
		symbol := frame.Symbol
		if symbol != "" && frame.Location > 0 {
			symbol = fmt.Sprintf("%s + %d", symbol, frame.Location)
		}
		result = append(result, Frame{Index: index, ImageIndex: frame.ImageIndex, Address: base + frame.ImageOffset, Symbol: symbol})
	}
	return result
}

var (
	crashThreadLine = regexp.MustCompile(`^(Thread \d+.*?|Last Exception Backtrace):?\s*$`)
	crashFrameLine  = regexp.MustCompile(`^(\d+)\s+(\S+(?: \S+)*?)\s+(0x[0-9a-fA-F]+)\s+(.*)$`)
	crashImageLine  = regexp.MustCompile(`^\s*(0x[0-9a-fA-F]+)\s+-\s+(0x[0-9a-fA-F]+)\s+\+?(\S+(?: \S+)*?)\s+(?:\(([^)]*)\)\s+)?(?:(\S+)\s+)?<([0-9a-fA-F-]+)>\s*(.*)$`)
	crashKeyValue   = regexp.MustCompile(`^(Process|Version):\s+(.*)$`)
)

func ParseCrash(data []byte) (Report, error) {
	var report Report
	var threads []Thread
	type pendingFrame struct {
		thread int
		image  string
		frame  Frame
	}
	var pending []pendingFrame
	inImages := false
	scanner := bufio.NewScanner(bytes.NewReader(data))
	scanner.Buffer(make([]byte, 0, 64*1024), 16*1024*1024)
	for scanner.Scan() {
		line := strings.TrimRight(scanner.Text(), "\r")
		trimmed := strings.TrimSpace(line)
		switch {
		case strings.HasPrefix(trimmed, "Binary Images:"):
			inImages = true
		case inImages:
			if match := crashImageLine.FindStringSubmatch(line); match != nil {
				base, _ := strconv.ParseUint(strings.TrimPrefix(match[1], "0x"), 16, 64)
				end, _ := strconv.ParseUint(strings.TrimPrefix(match[2], "0x"), 16, 64)
				report.Images = append(report.Images, Image{Name: match[3], Arch: match[5], UUID: NormalizeUUID(match[6]), Base: base, End: end, Path: strings.TrimSpace(match[7])})
			}
		case crashKeyValue.MatchString(trimmed):
			match := crashKeyValue.FindStringSubmatch(trimmed)
			if match[1] == "Process" && report.AppName == "" {
				report.AppName = strings.Fields(match[2])[0]
			} else if match[1] == "Version" && report.Version == "" {
				report.Version = match[2]
			}
		case crashThreadLine.MatchString(trimmed) && !strings.Contains(trimmed, "State"):
			name := strings.TrimSuffix(trimmed, ":")
			threads = append(threads, Thread{Name: name, Triggered: strings.Contains(name, "Crashed")})
		case len(threads) > 0 && crashFrameLine.MatchString(trimmed):
			match := crashFrameLine.FindStringSubmatch(trimmed)
			index, _ := strconv.Atoi(match[1])
			address, _ := strconv.ParseUint(strings.TrimPrefix(match[3], "0x"), 16, 64)
			pending = append(pending, pendingFrame{thread: len(threads) - 1, image: match[2], frame: Frame{Index: index, Address: address, Symbol: match[4]}})
		}
	}
	if err := scanner.Err(); err != nil {
		return Report{}, err
	}
	if len(threads) == 0 {
		return Report{}, fmt.Errorf("no threads found in the crash report")
	}
	for _, item := range pending {
		item.frame.ImageIndex = imageIndex(report.Images, item.image, item.frame.Address)
		threads[item.thread].Frames = append(threads[item.thread].Frames, item.frame)
	}
	report.Threads = threads
	return report, nil
}

func imageIndex(images []Image, name string, address uint64) int {
	for index, image := range images {
		if image.Base <= address && address <= image.End {
			return index
		}
	}
	for index, image := range images {
		if image.Name == name || strings.HasSuffix(image.Path, "/"+name) {
			return index
		}
	}
	return -1
}

func parenthesized(value string) string {
	if value == "" {
		return ""
	}
	return "(" + value + ")"
}

func firstNonEmpty(values ...string) string {
	for _, value := range values {
		if value != "" {
			return value
		}
	}
	return ""
}
