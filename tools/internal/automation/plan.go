package automation

import (
	"encoding/json"
	"fmt"
	"net/url"
	"os"
	"path/filepath"
	"strings"
	"time"
)

const CLIRequestID = "0A7C0DE5-0000-4000-8000-000000000031"

func Plan(ctx Context) []Case {
	return append(URLCases(ctx), CLICases(ctx)...)
}

func URLCases(ctx Context) []Case {
	fixture := QueryValue(ctx.Fixture)
	fileURL := QueryValue((&url.URL{Scheme: "file", Path: ctx.Fixture}).String())
	return []Case{
		{Name: "url-capture-region", URL: "ishare://capture/region", Check: completedWithStubLink},
		{Name: "url-capture-window", URL: "ishare://capture/window", Check: completedWithStubLink},
		{Name: "url-capture-screen-by-type", URL: "ishare://capture?type=screen", Check: completedWithStubLink},
		{Name: "url-capture-scrolling-callback", URL: "ishare://x-callback-url/capture/scrolling?x-success=ishare-automation://done", Check: all(completedWithStubLink, callbackStartsWith("ishare-automation://done?link=https"))},
		{Name: "url-capture-invalid-mode", URL: "ishare://capture/bogus", Check: rejected(4)},
		{Name: "url-record-start", URL: "ishare://record/start", Check: all(completed, recording(true))},
		{Name: "url-record-stop", URL: "ishare://record/stop", Check: all(completed, recording(false))},
		{Name: "url-record-toggle-gif-region", URL: "ishare://record/toggle?gif=1&region=1", Check: all(completed, recording(true))},
		{Name: "url-record-default-toggle", URL: "ishare://record", Check: all(completed, recording(false))},
		{Name: "url-record-invalid-action", URL: "ishare://record/pause", Check: rejected(4)},
		{Name: "url-upload-path", URL: "ishare://upload?path=" + fixture, Check: completedWithStubLink},
		{Name: "url-upload-legacy-file", URL: "ishare://upload?file=" + fileURL, Check: completedWithStubLink},
		{Name: "url-upload-missing-file", URL: "ishare://upload?path=%2Fnonexistent%2Fmissing.png&x-error=ishare-automation://failed", Check: all(rejected(5), callbackStartsWith("ishare-automation://failed?errorCode=5"))},
		{Name: "url-upload-without-path", URL: "ishare://upload", Check: rejected(3)},
		{Name: "url-uploader-select", URL: "ishare://uploader/select?name=" + QueryValue(StubUploader), Check: completed},
		{Name: "url-uploader-select-unknown", URL: "ishare://uploader/select?name=Nope&x-error=ishare-automation://failed", Check: all(outcome("failed"), callbackStartsWith("ishare-automation://failed?errorCode=100"))},
		{Name: "url-uploader-select-without-name", URL: "ishare://uploader/select", Check: rejected(3)},
		{Name: "url-open-history", URL: "ishare://open/history", Check: all(completed, opened("history"))},
		{Name: "url-open-settings", URL: "ishare://open/settings?pane=uploaders", Check: all(completed, opened("settings:uploaders"))},
		{Name: "url-open-editor", URL: "ishare://open/editor", Check: all(completed, opened("editor"))},
		{Name: "url-open-invalid-target", URL: "ishare://open/nowhere", Check: rejected(4)},
		{Name: "url-cli-unknown-request", URL: "ishare://cli?id=" + CLIRequestID, Check: all(completed, mailboxFailure(CLIRequestID))},
		{Name: "url-cli-without-id", URL: "ishare://cli", Check: rejected(3)},
		{Name: "url-cli-invalid-id", URL: "ishare://cli?id=not-a-uuid", Check: rejected(4)},
		{Name: "url-unknown-action", URL: "ishare://teleport", Check: rejected(2)},
		{Name: "url-forbidden-callback", URL: "ishare://capture/region?x-success=https://example.com", Check: rejected(7)},
	}
}

func CLICases(ctx Context) []Case {
	json := func(arguments ...string) []string {
		return append(arguments, "--json", "--timeout", "30")
	}
	return []Case{
		{Name: "cli-version", Args: []string{"--version"}, Check: all(exitCode(0), stdoutContains("."))},
		{Name: "cli-help", Args: []string{"--help"}, Check: all(exitCode(0), stdoutContains("Usage: ishare"))},
		{Name: "cli-usage-error", Args: []string{"capture"}, Check: exitCode(2)},
		{Name: "cli-unknown-command", Args: []string{"teleport"}, Check: exitCode(2)},
		{Name: "cli-uploaders-list", Args: json("uploaders", "list"), Check: all(exitCode(0), succeeded, stubUploaderSelected)},
		{Name: "cli-upload", Args: json("upload", ctx.Fixture), Check: all(exitCode(0), succeeded, uploadedToStub)},
		{Name: "cli-upload-named-uploader", Args: json("upload", ctx.Fixture, "--uploader", StubUploader), Check: all(exitCode(0), succeeded, uploadedToStub)},
		{Name: "cli-upload-missing-file", Args: json("upload", "/nonexistent/missing.png"), Check: all(exitCode(1), uploadFailed)},
		{Name: "cli-upload-unknown-uploader", Args: json("upload", ctx.Fixture, "--uploader", "Nope"), Check: all(exitCode(1), uploadFailed)},
		{Name: "cli-capture-region", Args: json("capture", "region"), Check: all(exitCode(0), succeeded, capturedFile)},
		{Name: "cli-capture-window-upload", Args: json("capture", "window", "--upload"), Check: all(exitCode(0), succeeded, capturedFile, capturedLink)},
		{Name: "cli-capture-screen", Args: json("capture", "screen"), Check: all(exitCode(0), succeeded, capturedFile)},
		{Name: "cli-capture-scrolling-upload", Args: json("capture", "scrolling", "--upload"), Check: all(exitCode(0), succeeded, capturedLink)},
		{Name: "cli-record-start", Args: json("record", "start"), Check: all(exitCode(0), succeeded, cliRecording(true))},
		{Name: "cli-record-stop", Args: json("record", "stop"), Check: all(exitCode(0), succeeded, cliRecording(false))},
		{Name: "cli-record-toggle-on", Args: json("record", "toggle"), Check: all(exitCode(0), succeeded, cliRecording(true))},
		{Name: "cli-record-toggle-off", Args: json("record", "toggle"), Check: all(exitCode(0), succeeded, cliRecording(false))},
		{Name: "cli-history", Args: json("history", "--limit", "3"), Check: all(exitCode(0), succeeded, historyCount(1, 3))},
		{Name: "cli-history-text", Args: []string{"history", "--limit", "1", "--timeout", "30"}, Timeout: 45 * time.Second, Check: all(exitCode(0), stdoutContains(StubHost))},
	}
}

type check = func(Context, Result) error

func all(checks ...check) check {
	return func(ctx Context, result Result) error {
		for _, check := range checks {
			if err := check(ctx, result); err != nil {
				return err
			}
		}
		return nil
	}
}

func outcome(expected string) check {
	return func(_ Context, result Result) error {
		if result.Reply == nil {
			return fmt.Errorf("no reply")
		}
		if result.Reply.Outcome != expected {
			return fmt.Errorf("outcome %q instead of %q (%s)", result.Reply.Outcome, expected, deref(result.Reply.ErrorMessage))
		}
		return nil
	}
}

var completed = outcome("completed")

func completedWithStubLink(ctx Context, result Result) error {
	if err := completed(ctx, result); err != nil {
		return err
	}
	if result.Reply.Link == nil {
		return fmt.Errorf("the action completed without a link")
	}
	return CheckStubLink(ctx, firstLine(*result.Reply.Link))
}

func rejected(code int) check {
	return func(ctx Context, result Result) error {
		if err := outcome("rejected")(ctx, result); err != nil {
			return err
		}
		if result.Reply.ErrorCode == nil || *result.Reply.ErrorCode != code {
			return fmt.Errorf("error code %v instead of %d", derefInt(result.Reply.ErrorCode), code)
		}
		return nil
	}
}

func recording(expected bool) check {
	return func(_ Context, result Result) error {
		if result.Reply == nil || result.Reply.Recording != expected {
			return fmt.Errorf("recording is not %t", expected)
		}
		return nil
	}
}

func opened(target string) check {
	return func(_ Context, result Result) error {
		if result.Reply == nil || !contains(result.Reply.Opened, target) {
			return fmt.Errorf("%s was not opened", target)
		}
		return nil
	}
}

func callbackStartsWith(prefix string) check {
	return func(_ Context, result Result) error {
		if result.Reply == nil || result.Reply.Callback == nil || !strings.HasPrefix(*result.Reply.Callback, prefix) {
			callback := ""
			if result.Reply != nil {
				callback = deref(result.Reply.Callback)
			}
			return fmt.Errorf("callback %q does not start with %q", callback, prefix)
		}
		return nil
	}
}

func mailboxFailure(id string) check {
	return func(ctx Context, _ Result) error {
		data, err := os.ReadFile(filepath.Join(ctx.Mailbox(), "responses", id+".json"))
		if err != nil {
			return fmt.Errorf("no response file: %w", err)
		}
		var response struct {
			Success bool `json:"success"`
		}
		if err := json.Unmarshal(data, &response); err != nil {
			return err
		}
		if response.Success {
			return fmt.Errorf("a request that was never written succeeded")
		}
		return nil
	}
}

func exitCode(expected int) check {
	return func(_ Context, result Result) error {
		if result.ExitCode != expected {
			return fmt.Errorf("exit code %d instead of %d", result.ExitCode, expected)
		}
		return nil
	}
}

func stdoutContains(text string) check {
	return func(_ Context, result Result) error {
		if !strings.Contains(result.Stdout, text) {
			return fmt.Errorf("the output does not contain %q", text)
		}
		return nil
	}
}

func envelope(result Result) (*Envelope, error) {
	if result.Envelope == nil {
		return nil, fmt.Errorf("no JSON output")
	}
	return result.Envelope, nil
}

func succeeded(_ Context, result Result) error {
	value, err := envelope(result)
	if err != nil {
		return err
	}
	if !value.Success {
		return fmt.Errorf("the command failed: %s", deref(value.Error))
	}
	return nil
}

func stubUploaderSelected(_ Context, result Result) error {
	value, err := envelope(result)
	if err != nil {
		return err
	}
	for _, uploader := range value.Payload.Uploaders {
		if uploader.Name == StubUploader && uploader.Selected && uploader.Kind == "folder" {
			return nil
		}
	}
	return fmt.Errorf("the stub uploader is not listed as the selected folder uploader")
}

func uploadedToStub(ctx Context, result Result) error {
	value, err := envelope(result)
	if err != nil {
		return err
	}
	if len(value.Payload.Uploads) != 1 || value.Payload.Uploads[0].Link == nil {
		return fmt.Errorf("expected one uploaded link, got %d uploads", len(value.Payload.Uploads))
	}
	return CheckStubLink(ctx, *value.Payload.Uploads[0].Link)
}

func uploadFailed(_ Context, result Result) error {
	value, err := envelope(result)
	if err != nil {
		return err
	}
	if len(value.Payload.Uploads) != 1 || value.Payload.Uploads[0].Error == nil || value.Payload.Uploads[0].Link != nil {
		return fmt.Errorf("expected one failed upload")
	}
	return nil
}

func capturedFile(_ Context, result Result) error {
	value, err := envelope(result)
	if err != nil {
		return err
	}
	if value.Payload.Capture == nil || value.Payload.Capture.File == nil {
		return fmt.Errorf("no captured file")
	}
	if _, err := os.Stat(*value.Payload.Capture.File); err != nil {
		return fmt.Errorf("the captured file is missing: %w", err)
	}
	return nil
}

func capturedLink(ctx Context, result Result) error {
	value, err := envelope(result)
	if err != nil {
		return err
	}
	if value.Payload.Capture == nil || value.Payload.Capture.Link == nil {
		return fmt.Errorf("the capture was not uploaded")
	}
	return CheckStubLink(ctx, *value.Payload.Capture.Link)
}

func cliRecording(expected bool) check {
	return func(_ Context, result Result) error {
		value, err := envelope(result)
		if err != nil {
			return err
		}
		if value.Payload.Recording == nil || *value.Payload.Recording != expected {
			return fmt.Errorf("recording is not %t", expected)
		}
		return nil
	}
}

func historyCount(minimum, maximum int) check {
	return func(_ Context, result Result) error {
		value, err := envelope(result)
		if err != nil {
			return err
		}
		if count := len(value.Payload.History); count < minimum || count > maximum {
			return fmt.Errorf("%d history entries instead of %d to %d", count, minimum, maximum)
		}
		return nil
	}
}

func firstLine(text string) string {
	line, _, _ := strings.Cut(text, "\n")
	return line
}

func deref(value *string) string {
	if value == nil {
		return ""
	}
	return *value
}

func derefInt(value *int) any {
	if value == nil {
		return nil
	}
	return *value
}
