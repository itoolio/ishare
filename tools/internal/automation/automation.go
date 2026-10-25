package automation

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"image"
	"image/color"
	"image/png"
	"io"
	"net/url"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"
)

const (
	ReplyParameter = "automation-test-id"
	StubHost       = "stub.ishare.test"
	StubUploader   = "Automation Stub"
	MailboxEnv     = "ISHARE_AUTOMATION_MAILBOX"
)

type Reply struct {
	Action       string   `json:"action"`
	Outcome      string   `json:"outcome"`
	Link         *string  `json:"link"`
	ErrorCode    *int     `json:"errorCode"`
	ErrorMessage *string  `json:"errorMessage"`
	Callback     *string  `json:"callback"`
	Recording    bool     `json:"recording"`
	Opened       []string `json:"opened"`
}

type Upload struct {
	File  string  `json:"file"`
	Link  *string `json:"link"`
	Error *string `json:"error"`
}

type Envelope struct {
	Success bool    `json:"success"`
	Error   *string `json:"error"`
	Payload struct {
		Message *string  `json:"message"`
		Uploads []Upload `json:"uploads"`
		Capture *struct {
			File *string `json:"file"`
			Link *string `json:"link"`
		} `json:"capture"`
		Uploaders []struct {
			ID       string `json:"id"`
			Name     string `json:"name"`
			Kind     string `json:"kind"`
			Selected bool   `json:"selected"`
		} `json:"uploaders"`
		History []struct {
			Link  *string `json:"link"`
			Title string  `json:"title"`
		} `json:"history"`
		Recording *bool `json:"recording"`
	} `json:"payload"`
}

type Result struct {
	Reply    *Reply
	Envelope *Envelope
	Stdout   string
	Stderr   string
	ExitCode int
}

type Context struct {
	Work    string
	Fixture string
}

func (c Context) Uploads() string { return filepath.Join(c.Work, "uploads") }
func (c Context) Mailbox() string { return filepath.Join(c.Work, "mailbox") }
func (c Context) Replies() string { return filepath.Join(c.Work, "replies") }

type Case struct {
	Name    string
	URL     string
	Args    []string
	Timeout time.Duration
	Check   func(Context, Result) error
}

func (c Case) IsURL() bool { return c.URL != "" }

func TaggedURL(raw, id string) (string, error) {
	parsed, err := url.Parse(raw)
	if err != nil {
		return "", err
	}
	if parsed.Scheme != "ishare" {
		return "", fmt.Errorf("%s is not an ishare:// URL", raw)
	}
	separator := "?"
	if strings.Contains(raw, "?") {
		separator = "&"
	}
	return raw + separator + ReplyParameter + "=" + QueryValue(id), nil
}

func QueryValue(value string) string {
	return strings.ReplaceAll(url.QueryEscape(value), "+", "%20")
}

func CheckStubLink(ctx Context, link string) error {
	parsed, err := url.Parse(link)
	if err != nil {
		return err
	}
	if parsed.Scheme != "https" || parsed.Host != StubHost {
		return fmt.Errorf("%s is not a link of the stub uploader", link)
	}
	relative := strings.TrimPrefix(parsed.Path, "/")
	if relative == "" || strings.Contains(relative, "..") {
		return fmt.Errorf("%s has no file path", link)
	}
	if _, err := os.Stat(filepath.Join(ctx.Uploads(), filepath.FromSlash(relative))); err != nil {
		return fmt.Errorf("the stub uploader did not store %s: %w", relative, err)
	}
	return nil
}

func WriteFixture(path string) error {
	canvas := image.NewRGBA(image.Rect(0, 0, 64, 40))
	for y := 0; y < 40; y++ {
		for x := 0; x < 64; x++ {
			canvas.Set(x, y, color.RGBA{R: uint8(x * 4), G: uint8(y * 6), B: 200, A: 255})
		}
	}
	var buffer bytes.Buffer
	if err := png.Encode(&buffer, canvas); err != nil {
		return err
	}
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return err
	}
	return os.WriteFile(path, buffer.Bytes(), 0o644)
}

type Executor interface {
	Run(ctx context.Context, env []string, name string, arguments ...string) (stdout, stderr string, exitCode int, err error)
}

type SystemExecutor struct{}

func (SystemExecutor) Run(ctx context.Context, env []string, name string, arguments ...string) (string, string, int, error) {
	command := exec.CommandContext(ctx, name, arguments...)
	command.Env = append(os.Environ(), env...)
	var stdout, stderr bytes.Buffer
	command.Stdout = &stdout
	command.Stderr = &stderr
	err := command.Run()
	var exitError *exec.ExitError
	if errors.As(err, &exitError) {
		return stdout.String(), stderr.String(), exitError.ExitCode(), nil
	}
	if err != nil {
		return stdout.String(), stderr.String(), -1, err
	}
	return stdout.String(), stderr.String(), 0, nil
}

type Options struct {
	App          string
	Work         string
	Output       io.Writer
	Executor     Executor
	ReadyTimeout time.Duration
	Poll         time.Duration
	Launch       bool
	Cases        []Case
}

type Failure struct {
	Case string
	Err  error
}

func (f Failure) Error() string { return f.Case + ": " + f.Err.Error() }

func LaunchArguments(app, work string) []string {
	return []string{
		"-n", "-g", "-a", app, "--args",
		"-ishareAutomationTestMode", "YES",
		"-ishareAutomationDirectory", work,
		"-ishareSkipOnboarding",
		"-AppleLanguages", "(en)",
		"-AppleLocale", "en_US",
	}
}

func Prepare(work string) (Context, error) {
	if err := os.RemoveAll(work); err != nil {
		return Context{}, err
	}
	ctx := Context{Work: work, Fixture: filepath.Join(work, "fixtures", "fixture image.png")}
	for _, directory := range []string{ctx.Mailbox(), ctx.Replies(), ctx.Uploads()} {
		if err := os.MkdirAll(directory, 0o755); err != nil {
			return Context{}, err
		}
	}
	return ctx, WriteFixture(ctx.Fixture)
}

func Run(options Options) ([]Failure, error) {
	if options.Executor == nil {
		options.Executor = SystemExecutor{}
	}
	if options.ReadyTimeout == 0 {
		options.ReadyTimeout = 90 * time.Second
	}
	if options.Poll == 0 {
		options.Poll = 200 * time.Millisecond
	}
	ctx, err := Prepare(options.Work)
	if err != nil {
		return nil, err
	}
	cases := options.Cases
	if cases == nil {
		cases = Plan(ctx)
	}
	if options.Launch {
		if _, stderr, code, err := options.Executor.Run(context.Background(), nil, "open", LaunchArguments(options.App, options.Work)...); err != nil || code != 0 {
			return nil, fmt.Errorf("launching %s failed (%d): %v %s", options.App, code, err, stderr)
		}
	}
	ready, err := waitForFile(filepath.Join(options.Work, "ready.json"), options.ReadyTimeout, options.Poll)
	if err != nil {
		return nil, fmt.Errorf("the app did not enter automation test mode: %w", err)
	}
	var pid struct {
		PID int `json:"pid"`
	}
	_ = json.Unmarshal(ready, &pid)
	fmt.Fprintf(options.Output, "ishare is ready in automation test mode (pid %d)\n", pid.PID)
	var failures []Failure
	for _, testCase := range cases {
		started := time.Now()
		result, err := execute(options, ctx, testCase)
		if err == nil && testCase.Check != nil {
			err = testCase.Check(ctx, result)
		}
		status := "ok"
		if err != nil {
			status = "FAIL"
			failures = append(failures, Failure{Case: testCase.Name, Err: err})
		}
		fmt.Fprintf(options.Output, "%-4s %-40s %6.2fs\n", status, testCase.Name, time.Since(started).Seconds())
		if err != nil {
			fmt.Fprintf(options.Output, "     %v\n", err)
			if result.Stdout != "" || result.Stderr != "" {
				fmt.Fprintf(options.Output, "     stdout: %s\n     stderr: %s\n", strings.TrimSpace(result.Stdout), strings.TrimSpace(result.Stderr))
			}
		}
	}
	if options.Launch && pid.PID > 0 {
		_, _, _, _ = options.Executor.Run(context.Background(), nil, "kill", fmt.Sprint(pid.PID))
	}
	fmt.Fprintf(options.Output, "%d of %d automation checks passed\n", len(cases)-len(failures), len(cases))
	return failures, nil
}

func timeout(testCase Case) time.Duration {
	if testCase.Timeout > 0 {
		return testCase.Timeout
	}
	return 45 * time.Second
}

func execute(options Options, ctx Context, testCase Case) (Result, error) {
	limit := timeout(testCase)
	runContext, cancel := context.WithTimeout(context.Background(), limit)
	defer cancel()
	if testCase.IsURL() {
		tagged, err := TaggedURL(testCase.URL, testCase.Name)
		if err != nil {
			return Result{}, err
		}
		replyPath := filepath.Join(ctx.Replies(), testCase.Name+".json")
		_ = os.Remove(replyPath)
		stdout, stderr, code, err := options.Executor.Run(runContext, nil, "open", "-g", "-a", options.App, tagged)
		result := Result{Stdout: stdout, Stderr: stderr, ExitCode: code}
		if err != nil || code != 0 {
			return result, fmt.Errorf("open exited with %d: %v", code, err)
		}
		data, err := waitForFile(replyPath, limit, options.Poll)
		if err != nil {
			return result, fmt.Errorf("no reply for %s: %w", testCase.URL, err)
		}
		var reply Reply
		if err := json.Unmarshal(data, &reply); err != nil {
			return result, fmt.Errorf("unreadable reply: %w", err)
		}
		result.Reply = &reply
		return result, nil
	}
	cli := filepath.Join(options.App, "Contents", "Helpers", "ishare")
	stdout, stderr, code, err := options.Executor.Run(runContext, []string{MailboxEnv + "=" + ctx.Mailbox()}, cli, testCase.Args...)
	result := Result{Stdout: stdout, Stderr: stderr, ExitCode: code}
	if runContext.Err() != nil {
		return result, fmt.Errorf("timed out after %s", limit)
	}
	if err != nil {
		return result, err
	}
	if contains(testCase.Args, "--json") && strings.HasPrefix(strings.TrimSpace(stdout), "{") {
		var envelope Envelope
		if err := json.Unmarshal([]byte(stdout), &envelope); err != nil {
			return result, fmt.Errorf("unreadable JSON output: %w", err)
		}
		result.Envelope = &envelope
	}
	return result, nil
}

func waitForFile(path string, limit, poll time.Duration) ([]byte, error) {
	deadline := time.Now().Add(limit)
	for {
		if data, err := os.ReadFile(path); err == nil && len(data) > 0 {
			return data, nil
		}
		if time.Now().After(deadline) {
			return nil, fmt.Errorf("%s did not appear within %s", filepath.Base(path), limit)
		}
		time.Sleep(poll)
	}
}

func contains(values []string, value string) bool {
	for _, candidate := range values {
		if candidate == value {
			return true
		}
	}
	return false
}
