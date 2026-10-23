package releasecheck

import (
	"encoding/json"
	"fmt"
	"os"
	"sort"
	"strings"
)

type ReviewTopic struct {
	Topic       string   `json:"topic"`
	Entitlement string   `json:"entitlement,omitempty"`
	Mentions    []string `json:"mentions"`
}

type Allowlist struct {
	Ignored     []string                     `json:"ignoredEntitlements"`
	Bundles     map[string]map[string]string `json:"bundles"`
	ReviewNotes []ReviewTopic                `json:"reviewNotes"`
}

func LoadAllowlist(path string) (Allowlist, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return Allowlist{}, err
	}
	return ParseAllowlist(data)
}

func ParseAllowlist(data []byte) (Allowlist, error) {
	var allowlist Allowlist
	if err := json.Unmarshal(data, &allowlist); err != nil {
		return Allowlist{}, fmt.Errorf("the entitlements allowlist is not valid JSON: %w", err)
	}
	if len(allowlist.Bundles) == 0 {
		return Allowlist{}, fmt.Errorf("the entitlements allowlist lists no bundles")
	}
	for bundle, entitlements := range allowlist.Bundles {
		for key, justification := range entitlements {
			if strings.TrimSpace(justification) == "" {
				return Allowlist{}, fmt.Errorf("%s: %s has no App Review justification in the allowlist", bundle, key)
			}
		}
	}
	for _, topic := range allowlist.ReviewNotes {
		if topic.Topic == "" || len(topic.Mentions) == 0 {
			return Allowlist{}, fmt.Errorf("every review notes topic needs a topic name and at least one mention")
		}
	}
	return allowlist, nil
}

func (allowlist Allowlist) ignores(key string) bool {
	for _, ignored := range allowlist.Ignored {
		if ignored == key {
			return true
		}
	}
	return false
}

func CheckEntitlements(bundleID string, entitlements map[string]any, allowlist Allowlist) []string {
	allowed, known := allowlist.Bundles[bundleID]
	if !known {
		return []string{fmt.Sprintf("%s is not in the entitlements allowlist; add the bundle and justify each of its entitlements in fastlane/entitlements-allowlist.json", bundleID)}
	}
	var problems []string
	for _, key := range sortedKeys(entitlements) {
		if allowlist.ignores(key) {
			continue
		}
		if enabled, isBool := entitlements[key].(bool); isBool && !enabled {
			continue
		}
		if _, ok := allowed[key]; !ok {
			problems = append(problems, fmt.Sprintf("%s has the new entitlement %s; App Review asks about every entitlement, so add it with a justification to fastlane/entitlements-allowlist.json and explain it in fastlane/review_notes.txt, or remove it", bundleID, key))
		}
	}
	return problems
}

func CheckReviewNotes(notes string, entitlements map[string]bool, allowlist Allowlist) []string {
	var problems []string
	lowered := strings.ToLower(notes)
	for _, topic := range allowlist.ReviewNotes {
		if topic.Entitlement != "" && !entitlements[topic.Entitlement] {
			continue
		}
		mentioned := false
		for _, mention := range topic.Mentions {
			if strings.Contains(lowered, strings.ToLower(mention)) {
				mentioned = true
				break
			}
		}
		if !mentioned {
			problems = append(problems, fmt.Sprintf("the App Review notes do not explain %s; mention %s in fastlane/review_notes.txt", topic.Topic, strings.Join(quoted(topic.Mentions), " or ")))
		}
	}
	return problems
}

func sortedKeys[V any](dictionary map[string]V) []string {
	keys := make([]string, 0, len(dictionary))
	for key := range dictionary {
		keys = append(keys, key)
	}
	sort.Strings(keys)
	return keys
}

func quoted(values []string) []string {
	result := make([]string, len(values))
	for index, value := range values {
		result[index] = fmt.Sprintf("%q", value)
	}
	return result
}
