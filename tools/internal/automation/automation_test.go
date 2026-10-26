package automation

import (
	"bytes"
	"context"
	"encoding/json"
	"net/url"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func TestTaggedURLAppendsTheReplyIDWithoutReencodingTheQuery(t *testing.T) {
	tagged, err := TaggedURL("ishare://upload?path=%2Ftmp%2Fa%20b.png", "url-upload")
	if err != nil {
		t.Fatal(err)
	}
	if tagged != "ishare://upload?path=%2Ftmp%2Fa%20b.png&automation-test-id=url-upload" {
		t.Fatalf("unexpected URL %s", tagged)
	}
	if tagged, _ := TaggedURL("ishare://capture/region", "x"); tagged != "ishare://capture/region?automation-test-id=x" {
		t.Fatalf("unexpected URL %s", tagged)
	}
	if _, err := TaggedURL("https://example.com", "x"); err == nil {
		t.Fatal("accepted a non-ishare URL")
	}
}

func TestQueryValueEncodesSpacesAsPercentTwenty(t *testing.T) {
	if value := QueryValue("/tmp/fixture image+1.png"); value != "%2Ftmp%2Ffixture%20image%2B1.png" {
		t.Fatalf("unexpected value %s", value)
	}
}

func TestPlanCoversEveryURLActionAndCLICommand(t *testing.T) {
	ctx := Context{Work: "/tmp/work", Fixture: "/tmp/work/fixtures/fixture image.png"}
	names := map[string]bool{}
	actions := map[string]bool{}
	commands := map[string]bool{}
	for _, testCase := range Plan(ctx) {
		if names[testCase.Name] {
			t.Errorf("duplicate case %s", testCase.Name)
		}
		names[testCase.Name] = true
		if testCase.Check == nil {
			t.Errorf("%s has no check", testCase.Name)
		}
		if testCase.IsURL() {
			parsed, err := url.Parse(testCase.URL)
			if err != nil {
				t.Fatalf("%s: %v", testCase.Name, err)
			}
			action := parsed.Host
			if action == "x-callback-url" {
				action = strings.Split(strings.TrimPrefix(parsed.Path, "/"), "/")[0]
			}
			actions[action] = true
		} else if len(testCase.Args) > 0 && !strings.HasPrefix(testCase.Args[0], "-") {
			commands[testCase.Args[0]] = true
		}
	}
	for _, action := range []string{"capture", "record", "upload", "uploader", "open", "cli"} {
		if !actions[action] {
			t.Errorf("no URL case for %s", action)
		}
	}
	for _, command := range []string{"upload", "capture", "record", "uploaders", "history"} {
		if !commands[command] {
			t.Errorf("no CLI case for %s", command)
		}
	}
}

func TestCheckStubLinkRequiresTheStoredFile(t *testing.T) {
	ctx := Context{Work: t.TempDir()}
	if err := os.MkdirAll(filepath.Join(ctx.Uploads(), "2026"), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(ctx.Uploads(), "2026", "a b.png"), []byte("png"), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := CheckStubLink(ctx, "https://stub.ishare.test/2026/a%20b.png"); err != nil {
		t.Fatal(err)
	}
	for _, link := range []string{"https://stub.ishare.test/2026/missing.png", "https://example.com/2026/a%20b.png", "http://stub.ishare.test/2026/a%20b.png", "https://stub.ishare.test/../etc"} {
		if CheckStubLink(ctx, link) == nil {
			t.Errorf("accepted %s", link)
		}
	}
}

func TestChecksReportMismatches(t *testing.T) {
	code := 5
	other := 3
	reply := Result{Reply: &Reply{Outcome: "rejected", ErrorCode: &code}}
	if err := rejected(5)(Context{}, reply); err != nil {
		t.Fatal(err)
	}
	if rejected(3)(Context{}, Result{Reply: &Reply{Outcome: "rejected", ErrorCode: &other}}) != nil {
		t.Fatal("matching code was rejected")
	}
	if rejected(4)(Context{}, reply) == nil {
		t.Fatal("wrong error code passed")
	}
	if completed(Context{}, reply) == nil {
		t.Fatal("a rejected reply passed as completed")
	}
	if recording(true)(Context{}, Result{Reply: &Reply{Recording: false}}) == nil {
		t.Fatal("recording mismatch passed")
	}
	if exitCode(0)(Context{}, Result{ExitCode: 1}) == nil {
		t.Fatal("exit code mismatch passed")
	}
	var envelope Envelope
	if err := json.Unmarshal([]byte(`{"success":true,"payload":{"uploaders":[{"id":"x","name":"Automation Stub","kind":"folder","selected":true}],"recording":true}}`), &envelope); err != nil {
		t.Fatal(err)
	}
	result := Result{Envelope: &envelope}
	for _, check := range []check{succeeded, stubUploaderSelected, cliRecording(true)} {
		if err := check(Context{}, result); err != nil {
			t.Fatal(err)
		}
	}
	if cliRecording(false)(Context{}, result) == nil || historyCount(1, 3)(Context{}, result) == nil {
		t.Fatal("mismatches passed")
	}
}

type fakeApp struct {
	t        *testing.T
	work     string
	launched bool
	opened   []string
	cli      [][]string
	env      []string
}

func (f *fakeApp) Run(_ context.Context, env []string, name string, arguments ...string) (string, string, int, error) {
	switch {
	case name == "open" && len(arguments) > 4 && arguments[4] == "--args":
		f.launched = true
		_ = os.WriteFile(filepath.Join(f.work, "ready.json"), []byte(`{"pid": 0}`), 0o644)
		return "", "", 0, nil
	case name == "open":
		target := arguments[len(arguments)-1]
		f.opened = append(f.opened, target)
		parsed, _ := url.Parse(target)
		id := parsed.Query().Get(ReplyParameter)
		reply := Reply{Action: parsed.Host, Outcome: "completed"}
		data, _ := json.Marshal(reply)
		_ = os.WriteFile(filepath.Join(f.work, "replies", id+".json"), data, 0o644)
		return "", "", 0, nil
	case name == "kill":
		return "", "", 0, nil
	default:
		f.cli = append(f.cli, append([]string{name}, arguments...))
		f.env = env
		return `{"success": true, "payload": {}}`, "", 0, nil
	}
}

func TestRunLaunchesTheAppAndCollectsRepliesAndOutputs(t *testing.T) {
	work := filepath.Join(t.TempDir(), "work")
	app := &fakeApp{t: t, work: work}
	cases := []Case{
		{Name: "url-capture-region", URL: "ishare://capture/region", Check: completed, Timeout: time.Second},
		{Name: "cli-history", Args: []string{"history", "--json"}, Check: all(exitCode(0), succeeded), Timeout: time.Second},
		{Name: "cli-failing", Args: []string{"history", "--json"}, Check: exitCode(3), Timeout: time.Second},
	}
	var output bytes.Buffer
	failures, err := Run(Options{App: "/Applications/ishare.app", Work: work, Output: &output, Executor: app, Launch: true, Cases: cases, Poll: 5 * time.Millisecond, ReadyTimeout: time.Second})
	if err != nil {
		t.Fatal(err)
	}
	if !app.launched || len(app.opened) != 1 || len(app.cli) != 2 {
		t.Fatalf("launched %t, opened %v, cli %v", app.launched, app.opened, app.cli)
	}
	if app.cli[0][0] != "/Applications/ishare.app/Contents/Helpers/ishare" {
		t.Fatalf("ran %s instead of the bundled CLI", app.cli[0][0])
	}
	if len(app.env) != 1 || app.env[0] != MailboxEnv+"="+filepath.Join(work, "mailbox") {
		t.Fatalf("unexpected environment %v", app.env)
	}
	if len(failures) != 1 || failures[0].Case != "cli-failing" {
		t.Fatalf("unexpected failures %v", failures)
	}
	if !strings.Contains(output.String(), "2 of 3 automation checks passed") {
		t.Fatalf("unexpected output %s", output.String())
	}
	if _, err := os.Stat(filepath.Join(work, "fixtures", "fixture image.png")); err != nil {
		t.Fatal(err)
	}
}

func TestRunFailsWhenTheAppNeverBecomesReady(t *testing.T) {
	work := filepath.Join(t.TempDir(), "work")
	_, err := Run(Options{App: "/Applications/ishare.app", Work: work, Output: &bytes.Buffer{}, Executor: &fakeApp{work: t.TempDir()}, Launch: false, Cases: []Case{}, Poll: time.Millisecond, ReadyTimeout: 20 * time.Millisecond})
	if err == nil || !strings.Contains(err.Error(), "automation test mode") {
		t.Fatalf("unexpected error %v", err)
	}
}

func TestMissingReplyTimesOut(t *testing.T) {
	work := filepath.Join(t.TempDir(), "work")
	executor := &silentApp{work: work}
	failures, err := Run(Options{App: "/a.app", Work: work, Output: &bytes.Buffer{}, Executor: executor, Launch: true, Poll: time.Millisecond, ReadyTimeout: time.Second,
		Cases: []Case{{Name: "url-x", URL: "ishare://capture", Check: completed, Timeout: 30 * time.Millisecond}}})
	if err != nil {
		t.Fatal(err)
	}
	if len(failures) != 1 || !strings.Contains(failures[0].Error(), "no reply") {
		t.Fatalf("unexpected failures %v", failures)
	}
}

type silentApp struct{ work string }

func (s *silentApp) Run(_ context.Context, _ []string, name string, arguments ...string) (string, string, int, error) {
	if name == "open" && len(arguments) > 4 && arguments[4] == "--args" {
		_ = os.WriteFile(filepath.Join(s.work, "ready.json"), []byte(`{"pid": 0}`), 0o644)
	}
	return "", "", 0, nil
}

func TestLaunchArgumentsEnableTheTestMode(t *testing.T) {
	arguments := strings.Join(LaunchArguments("/a.app", "/w"), " ")
	if !strings.Contains(arguments, "-ishareAutomationTestMode YES") || !strings.Contains(arguments, "-ishareAutomationDirectory /w") || !strings.HasPrefix(arguments, "-n -g -a /a.app --args") {
		t.Fatalf("unexpected arguments %s", arguments)
	}
}
