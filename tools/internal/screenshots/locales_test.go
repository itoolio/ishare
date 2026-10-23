package screenshots

import (
	"reflect"
	"testing"
)

func TestParseTargetsKnowsTheAppStoreLocales(t *testing.T) {
	got, err := ParseTargets([]string{"zh-Hans", "ar-SA", "hi"})
	want := []Target{{"zh-Hans", "zh-CN"}, {"ar-SA", "ar"}, {"hi", "hi"}}
	if err != nil || !reflect.DeepEqual(got, want) {
		t.Fatalf("unexpected targets %v, %v", got, err)
	}
	all, err := ParseTargets([]string{"all"})
	if err != nil || len(all) != 11 || all[0] != (Target{"en-US", "en"}) || all[10] != (Target{"zh-Hans", "zh-CN"}) {
		t.Fatalf("unexpected targets for all: %v, %v", all, err)
	}
}
