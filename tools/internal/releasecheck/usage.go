package releasecheck

import (
	"fmt"
	"regexp"
	"sort"
	"strings"
)

type UsageRequirement struct {
	Reason       string
	Alternatives []string
}

var entitlementUsage = map[string][]string{
	"com.apple.security.device.camera":                       {"NSCameraUsageDescription"},
	"com.apple.security.device.audio-input":                  {"NSMicrophoneUsageDescription"},
	"com.apple.security.device.bluetooth":                    {"NSBluetoothAlwaysUsageDescription"},
	"com.apple.security.personal-information.location":       {"NSLocationUsageDescription", "NSLocationWhenInUseUsageDescription"},
	"com.apple.security.personal-information.addressbook":    {"NSContactsUsageDescription"},
	"com.apple.security.personal-information.calendars":      {"NSCalendarsUsageDescription", "NSCalendarsFullAccessUsageDescription", "NSCalendarsWriteOnlyAccessUsageDescription"},
	"com.apple.security.personal-information.photos-library": {"NSPhotoLibraryUsageDescription", "NSPhotoLibraryAddUsageDescription"},
	"com.apple.security.automation.apple-events":             {"NSAppleEventsUsageDescription"},
}

var frameworkUsage = map[string][]string{
	"ScreenCaptureKit": {"NSScreenCaptureUsageDescription"},
	"Contacts":         {"NSContactsUsageDescription"},
	"CoreLocation":     {"NSLocationUsageDescription", "NSLocationWhenInUseUsageDescription"},
	"EventKit":         {"NSCalendarsUsageDescription", "NSCalendarsFullAccessUsageDescription", "NSRemindersUsageDescription", "NSRemindersFullAccessUsageDescription"},
	"Photos":           {"NSPhotoLibraryUsageDescription", "NSPhotoLibraryAddUsageDescription"},
	"Speech":           {"NSSpeechRecognitionUsageDescription"},
	"CoreBluetooth":    {"NSBluetoothAlwaysUsageDescription"},
	"HomeKit":          {"NSHomeKitUsageDescription"},
	"Intents":          {"NSSiriUsageDescription"},
	"CoreMotion":       {"NSMotionUsageDescription"},
}

var frameworkPath = regexp.MustCompile(`/([^/]+)\.framework/`)

func ParseLinkedFrameworks(otoolOutput string) []string {
	seen := map[string]bool{}
	var frameworks []string
	for _, line := range strings.Split(otoolOutput, "\n") {
		if !strings.HasPrefix(line, "\t") && !strings.HasPrefix(line, " ") {
			continue
		}
		match := frameworkPath.FindStringSubmatch(line)
		if match == nil || seen[match[1]] {
			continue
		}
		seen[match[1]] = true
		frameworks = append(frameworks, match[1])
	}
	sort.Strings(frameworks)
	return frameworks
}

func RequiredUsageDescriptions(frameworks []string, entitlements map[string]any) []UsageRequirement {
	var requirements []UsageRequirement
	for _, framework := range frameworks {
		if keys, ok := frameworkUsage[framework]; ok {
			requirements = append(requirements, UsageRequirement{Reason: "links " + framework + ".framework", Alternatives: keys})
		}
	}
	for _, key := range sortedKeys(entitlements) {
		if enabled, isBool := entitlements[key].(bool); isBool && !enabled {
			continue
		}
		if keys, ok := entitlementUsage[key]; ok {
			requirements = append(requirements, UsageRequirement{Reason: "has the " + key + " entitlement", Alternatives: keys})
		}
	}
	return requirements
}

func CheckUsageDescriptions(bundleID string, info map[string]any, requirements []UsageRequirement) []string {
	var problems []string
	for _, requirement := range requirements {
		satisfied := false
		for _, key := range requirement.Alternatives {
			if text, ok := info[key].(string); ok && strings.TrimSpace(text) != "" {
				satisfied = true
				break
			}
		}
		if !satisfied {
			problems = append(problems, fmt.Sprintf("%s %s but its Info.plist has no %s", bundleID, requirement.Reason, strings.Join(requirement.Alternatives, " or ")))
		}
	}
	return problems
}
