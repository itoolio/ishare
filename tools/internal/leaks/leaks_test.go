package leaks

import "testing"

func TestParsesTheLeaksSummary(t *testing.T) {
	summary, err := ParseLeaks("Process 4242: 63891 nodes malloced for 9100 KB\nProcess 4242: 3 leaks for 1,536 total leaked bytes.\n")
	if err != nil || summary.Leaks != 3 || summary.Bytes != 1536 {
		t.Fatalf("unexpected %+v %v", summary, err)
	}
	single, err := ParseLeaks("Process 1: 1 leak for 48 total leaked bytes.")
	if err != nil || single.Leaks != 1 || single.Bytes != 48 {
		t.Fatalf("unexpected %+v %v", single, err)
	}
	if _, err := ParseLeaks("leaks: could not attach"); err == nil {
		t.Fatal("expected an error without a summary")
	}
}

func TestParsesTheFootprint(t *testing.T) {
	footprint, err := ParseFootprint("ishare [4242]: 64-bit\n  phys_footprint: 182.5 MB\n")
	if err != nil || footprint.Bytes != int64(182.5*1024*1024) {
		t.Fatalf("unexpected %+v %v", footprint, err)
	}
	if _, err := ParseFootprint("nothing"); err == nil {
		t.Fatal("expected an error")
	}
}

func TestChecksLeaksAndGrowthAgainstTheLimits(t *testing.T) {
	limits := Limits{MaxLeaks: 2, MaxGrowthBytes: 20 << 20}
	if problems := Check(Summary{Leaks: 2}, Footprint{Bytes: 100 << 20}, Footprint{Bytes: 110 << 20}, limits); len(problems) != 0 {
		t.Fatalf("unexpected problems %v", problems)
	}
	if problems := Check(Summary{Leaks: 5, Bytes: 800}, Footprint{Bytes: 100 << 20}, Footprint{Bytes: 150 << 20}, limits); len(problems) != 2 {
		t.Fatalf("expected two problems, got %v", problems)
	}
}

func TestDiscountsLeaksRootedInSystemServiceConnections(t *testing.T) {
	report := `Process 14425: 195 leaks for 12544 total leaked bytes.

STACK OF 1 INSTANCE OF 'ROOT CYCLE: <NSXPCConnection>':
====
    96 (6.12K) ROOT CYCLE: <NSXPCConnection 0xa18c6c900> [192]  Connection: "com.apple.linkd.autoShortcut" [no process]
       6 (800 bytes) _connection --> ROOT CYCLE: <xpc_connection_t 0xa190b5040> [320]  "com.apple.linkd.autoShortcut"

STACK OF 1 INSTANCE OF 'ROOT CYCLE: <NSXPCConnection>':
2   libobjc.A.dylib                       0x187b69f64 _objc_rootAllocWithZone + 52
====
      96 (6.12K) ROOT CYCLE: <NSXPCConnection 0xa18c6c600> [192]  Protocol: LNDaemonApplicationInterface  Connection: "com.apple.linkd.autoShortcut" [no process]
            4 (432 bytes) ROOT CYCLE: <dispatch_mach_t 0xa18dfe760> [160]  "com.apple.linkd.autoShortcut"

STACK OF 1 INSTANCE OF 'ROOT LEAK: <UploadTask>':
====
      3 (144 bytes) ROOT LEAK: <UploadTask 0xa18c70000> [48]
`
	summary, err := ParseLeaks(report)
	if err != nil || summary.Leaks != 195 || summary.SystemLeaks != 192 || summary.OwnLeaks() != 3 {
		t.Fatalf("unexpected %+v %v", summary, err)
	}
	if problems := Check(summary, Footprint{}, Footprint{}, Limits{MaxLeaks: 2}); len(problems) != 1 {
		t.Fatalf("own leaks should still count, got %v", problems)
	}
	if problems := Check(summary, Footprint{}, Footprint{}, Limits{MaxLeaks: 3}); len(problems) != 0 {
		t.Fatalf("unexpected problems %v", problems)
	}
}
