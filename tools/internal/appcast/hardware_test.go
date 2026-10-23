package appcast

import (
	"strings"
	"testing"
)

const feed = `<?xml version="1.0" standalone="yes"?>
<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" version="2.0">
    <channel>
        <title>ishare</title>
        <item>
            <title>5.3.0</title>
            <sparkle:version>700</sparkle:version>
        </item>
    </channel>
</rss>
`

func TestRequireHardwareAddsTheElementToEveryItem(t *testing.T) {
	got, changed, err := RequireHardware(feed, "arm64")
	if err != nil || changed != 1 {
		t.Fatalf("changed %d, err %v", changed, err)
	}
	want := "            <sparkle:version>700</sparkle:version>\n            <sparkle:hardwareRequirements>arm64</sparkle:hardwareRequirements>\n        </item>"
	if !strings.Contains(got, want) {
		t.Fatalf("unexpected feed:\n%s", got)
	}
}

func TestRequireHardwareIsIdempotent(t *testing.T) {
	once, _, _ := RequireHardware(feed, "arm64")
	twice, changed, err := RequireHardware(once, "arm64")
	if err != nil || changed != 0 || twice != once {
		t.Fatalf("second pass changed %d items, err %v", changed, err)
	}
}

func TestRequireHardwareRejectsEmptyFeeds(t *testing.T) {
	if _, _, err := RequireHardware("<rss></rss>", "arm64"); err == nil {
		t.Fatal("expected an error for a feed without items")
	}
}
