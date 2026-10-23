package plist

import (
	"reflect"
	"testing"
)

const sample = `<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>com.apple.security.app-sandbox</key>
	<true/>
	<key>com.apple.security.get-task-allow</key>
	<false/>
	<key>com.apple.security.application-groups</key>
	<array>
		<string>L988J7YMK5.group.dev.adrian.ishare</string>
	</array>
	<key>Count</key>
	<integer>3</integer>
	<key>Scale</key>
	<real>2.5</real>
	<key>Blob</key>
	<data>aGVs
	bG8=</data>
	<key>Nested</key>
	<dict>
		<key>Empty</key>
		<dict/>
	</dict>
</dict>
</plist>`

func TestParseReadsEveryValueType(t *testing.T) {
	dictionary, err := ParseDictionary([]byte(sample))
	if err != nil {
		t.Fatal(err)
	}
	expected := map[string]any{
		"com.apple.security.app-sandbox":        true,
		"com.apple.security.get-task-allow":     false,
		"com.apple.security.application-groups": []any{"L988J7YMK5.group.dev.adrian.ishare"},
		"Count":                                 int64(3),
		"Scale":                                 2.5,
		"Blob":                                  []byte("hello"),
		"Nested":                                map[string]any{"Empty": map[string]any{}},
	}
	if !reflect.DeepEqual(dictionary, expected) {
		t.Fatalf("got %#v", dictionary)
	}
}

func TestParseDictionaryRejectsOtherRoots(t *testing.T) {
	if _, err := ParseDictionary([]byte(`<plist><array/></plist>`)); err == nil {
		t.Fatal("an array root was accepted")
	}
	if _, err := ParseDictionary([]byte(``)); err == nil {
		t.Fatal("an empty document was accepted")
	}
}
