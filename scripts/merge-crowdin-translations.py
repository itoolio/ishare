import json
import sys

LANGUAGE_ALIASES = {"zh-Hans": "zh-CN", "zh_CN": "zh-CN"}


def dump(value, indent=0):
    pad = "  " * indent
    if isinstance(value, dict):
        if not value:
            return "{\n\n" + pad + "}"
        items = [("  " * (indent + 1)) + json.dumps(key, ensure_ascii=False) + " : " + dump(item, indent + 1) for key, item in value.items()]
        return "{\n" + ",\n".join(items) + "\n" + pad + "}"
    if isinstance(value, list):
        if not value:
            return "[\n\n" + pad + "]"
        return "[\n" + ",\n".join(("  " * (indent + 1)) + dump(item, indent + 1) for item in value) + "\n" + pad + "]"
    return json.dumps(value, ensure_ascii=False)


def translated_value(localization):
    unit = localization.get("stringUnit")
    if not unit or unit.get("state") not in ("translated", "needs_review", None):
        return None
    value = unit.get("value") or ""
    return value if value.strip() else None


def has_value(localization):
    if localization is None:
        return False
    if "stringUnit" in localization:
        return translated_value(localization) is not None
    return True


def merge(base, incoming):
    shipped = {language for entry in base["strings"].values() for language in entry.get("localizations", {})}
    added = []
    for key, entry in incoming["strings"].items():
        if key not in base["strings"]:
            continue
        target = base["strings"][key]
        if target.get("shouldTranslate") is False:
            continue
        for language, localization in entry.get("localizations", {}).items():
            language = LANGUAGE_ALIASES.get(language, language)
            if language == base.get("sourceLanguage", "en"):
                continue
            value = translated_value(localization)
            if value is None or value == key:
                continue
            existing = target.get("localizations", {}).get(language)
            if has_value(existing):
                continue
            target.setdefault("localizations", {})[language] = {"stringUnit": {"state": "translated", "value": value}}
            target["localizations"] = dict(sorted(target["localizations"].items()))
            added.append((language, key, language in shipped))
    return added


def main():
    base_path, incoming_path, output_path = sys.argv[1:4]
    with open(base_path, encoding="utf-8") as handle:
        base = json.load(handle)
    with open(incoming_path, encoding="utf-8") as handle:
        incoming = json.load(handle)
    added = merge(base, incoming)
    with open(output_path, "w", encoding="utf-8") as handle:
        handle.write(dump(base))
    languages = sorted({language for language, _, _ in added})
    print(f"added={len(added)}")
    print(f"languages={','.join(languages)}")


if __name__ == "__main__":
    main()
