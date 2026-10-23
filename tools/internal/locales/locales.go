package locales

type Locale struct {
	AppStore string
	Catalog  string
}

const SourceAppStore = "en-US"

var All = []Locale{
	{AppStore: "en-US", Catalog: "en"},
	{AppStore: "ar-SA", Catalog: "ar"},
	{AppStore: "de-DE", Catalog: "de"},
	{AppStore: "es-ES", Catalog: "es"},
	{AppStore: "fr-FR", Catalog: "fr"},
	{AppStore: "hi", Catalog: "hi"},
	{AppStore: "ja", Catalog: "ja"},
	{AppStore: "ko", Catalog: "ko"},
	{AppStore: "tr", Catalog: "tr"},
	{AppStore: "uk", Catalog: "uk"},
	{AppStore: "zh-Hans", Catalog: "zh-CN"},
}

func ByAppStore(code string) (Locale, bool) {
	for _, locale := range All {
		if locale.AppStore == code {
			return locale, true
		}
	}
	return Locale{}, false
}

func AppStoreCodes() []string {
	codes := make([]string, len(All))
	for index, locale := range All {
		codes[index] = locale.AppStore
	}
	return codes
}
