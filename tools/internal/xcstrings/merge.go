package xcstrings

import (
	"fmt"
	"sort"
	"strings"
	"unicode"
)

var languageAliases = map[string]string{"zh-Hans": "zh-CN", "zh_CN": "zh-CN"}

type Addition struct {
	Language string
	Key      string
}

type Result struct {
	Additions []Addition
}

func (result Result) Languages() []string {
	unique := map[string]bool{}
	for _, addition := range result.Additions {
		unique[addition.Language] = true
	}
	languages := make([]string, 0, len(unique))
	for language := range unique {
		languages = append(languages, language)
	}
	sort.Strings(languages)
	return languages
}

func (result Result) Summary() string {
	return fmt.Sprintf("added=%d\nlanguages=%s\n", len(result.Additions), strings.Join(result.Languages(), ","))
}

func Merge(base, incoming *Value) (Result, error) {
	baseStrings := base.Get("strings")
	incomingStrings := incoming.Get("strings")
	if baseStrings == nil || baseStrings.Kind != Object || incomingStrings == nil || incomingStrings.Kind != Object {
		return Result{}, fmt.Errorf("both catalogs need a \"strings\" object")
	}
	sourceLanguage := "en"
	if text, ok := base.Get("sourceLanguage").Text(); ok {
		sourceLanguage = text
	}
	var result Result
	for _, member := range incomingStrings.Members {
		target := baseStrings.Get(member.Key)
		if target == nil || target.Get("shouldTranslate").IsFalse() {
			continue
		}
		localizations := member.Value.Get("localizations")
		if localizations == nil {
			continue
		}
		for _, localization := range localizations.Members {
			language := alias(localization.Key)
			if language == sourceLanguage {
				continue
			}
			value, ok := translatedValue(localization.Value)
			if !ok || value == member.Key {
				continue
			}
			if hasValue(target.Get("localizations").Get(language)) {
				continue
			}
			addTranslation(target, language, value)
			result.Additions = append(result.Additions, Addition{Language: language, Key: member.Key})
		}
	}
	return result, nil
}

func MergeFiles(baseData, incomingData []byte) ([]byte, Result, error) {
	base, err := Parse(baseData)
	if err != nil {
		return nil, Result{}, fmt.Errorf("couldn't read the base catalog: %w", err)
	}
	incoming, err := Parse(incomingData)
	if err != nil {
		return nil, Result{}, fmt.Errorf("couldn't read the incoming catalog: %w", err)
	}
	result, err := Merge(base, incoming)
	if err != nil {
		return nil, Result{}, err
	}
	return Format(base), result, nil
}

func alias(language string) string {
	if replacement, ok := languageAliases[language]; ok {
		return replacement
	}
	return language
}

func addTranslation(target *Value, language, text string) {
	localizations := target.Get("localizations")
	if localizations == nil {
		localizations = NewObject()
		target.Set("localizations", localizations)
	}
	localizations.Set(language, NewObject(Member{Key: "stringUnit", Value: NewObject(
		Member{Key: "state", Value: NewString("translated")},
		Member{Key: "value", Value: NewString(text)},
	)}))
	localizations.SortMembers()
}

func translatedValue(localization *Value) (string, bool) {
	unit := localization.Get("stringUnit")
	if !truthy(unit) {
		return "", false
	}
	if unit.Has("state") {
		state := unit.Get("state")
		text, isText := state.Text()
		if state.Kind != Null && (!isText || (text != "translated" && text != "needs_review")) {
			return "", false
		}
	}
	text, _ := unit.Get("value").Text()
	if strings.TrimFunc(text, isPythonSpace) == "" {
		return "", false
	}
	return text, true
}

func hasValue(localization *Value) bool {
	if localization == nil {
		return false
	}
	if localization.Has("stringUnit") {
		_, ok := translatedValue(localization)
		return ok
	}
	return true
}

func truthy(value *Value) bool {
	if value == nil {
		return false
	}
	switch value.Kind {
	case Null:
		return false
	case Bool:
		return value.Bool
	case String:
		return value.String != ""
	case Object:
		return len(value.Members) > 0
	case Array:
		return len(value.Items) > 0
	default:
		return value.Number != "0" && value.Number != "0.0"
	}
}

func isPythonSpace(character rune) bool {
	return unicode.IsSpace(character) || (character >= 0x1c && character <= 0x1f)
}
