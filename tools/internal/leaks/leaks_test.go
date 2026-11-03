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
