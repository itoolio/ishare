#!/bin/zsh
set -euo pipefail

ROOT=${0:A:h:h}
LOCALE=${1:-en-US}
LANGUAGE=${2:-en}
OUTPUT="$ROOT/fastlane/screenshots/$LOCALE"
WORK="$ROOT/build/screenshots"
RESULT="$WORK/Screenshots-$LOCALE.xcresult"

rm -rf "$WORK" "$OUTPUT"
mkdir -p "$WORK/attachments" "$OUTPUT"

cd "$ROOT"
command -v xcodegen >/dev/null && xcodegen generate --quiet

TEST_RUNNER_ISHARE_LANGUAGE="$LANGUAGE" xcodebuild test \
  -project ishare.xcodeproj \
  -scheme Screenshots \
  -destination "platform=macOS" \
  -derivedDataPath "$WORK/DerivedData" \
  -resultBundlePath "$RESULT" \
  CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= PROVISIONING_PROFILE_SPECIFIER= \
  | (command -v xcbeautify >/dev/null && xcbeautify || cat)

xcrun xcresulttool export attachments --path "$RESULT" --output-path "$WORK/attachments"

python3 - "$WORK/attachments" "$OUTPUT" <<'PY'
import json, os, shutil, subprocess, sys
source, destination = sys.argv[1], sys.argv[2]
manifest = json.load(open(os.path.join(source, "manifest.json")))
count = 0
for test in manifest:
    for attachment in test.get("attachments", []):
        name = attachment.get("suggestedHumanReadableName", "")
        stem = name.split("_0_")[0].rsplit(".", 1)[0]
        target = os.path.join(destination, f"{stem}.png")
        shutil.copy(os.path.join(source, attachment["exportedFileName"]), target)
        subprocess.run(["sips", "-z", "1800", "2880", target], check=True, capture_output=True)
        count += 1
if count == 0:
    sys.exit("No screenshots were exported")
print(f"Exported {count} screenshots to {destination}")
PY
