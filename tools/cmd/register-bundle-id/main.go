package main

import (
	"bytes"
	"crypto/ecdsa"
	"crypto/rand"
	"crypto/sha256"
	"crypto/x509"
	"encoding/base64"
	"encoding/json"
	"encoding/pem"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"os"
	"strings"
	"time"

	"github.com/itoolio/ishare/tools/internal/repo"
)

const bundleIDsEndpoint = "https://api.appstoreconnect.apple.com/v1/bundleIds"

type bundleIDList struct {
	Data []struct {
		Attributes struct {
			Identifier string `json:"identifier"`
		} `json:"attributes"`
	} `json:"data"`
}

func main() {
	identifiers := strings.Split(requiredEnv("BUNDLE_IDENTIFIERS"), ",")
	name := os.Getenv("BUNDLE_NAME")
	if name == "" {
		name = "ishare"
	}
	token, err := signedToken(requiredEnv("KEY_ID"), requiredEnv("ISSUER_ID"), requiredEnv("PRIVATE_KEY_BASE64"))
	if err != nil {
		repo.Fail(err)
	}
	for _, raw := range identifiers {
		identifier := strings.TrimSpace(raw)
		if identifier == "" {
			continue
		}
		registered, err := isRegistered(token, identifier)
		if err != nil {
			repo.Fail(err)
		}
		if registered {
			fmt.Println(identifier, "is already registered")
			continue
		}
		if err := register(token, identifier, displayName(name, identifier)); err != nil {
			repo.Fail(err)
		}
		fmt.Println("Registered", identifier)
	}
}

func displayName(base, identifier string) string {
	suffix := identifier[strings.LastIndex(identifier, ".")+1:]
	if strings.EqualFold(suffix, base) {
		return base
	}
	return base + " " + suffix
}

func requiredEnv(name string) string {
	value := os.Getenv(name)
	if value == "" {
		repo.Fail(fmt.Errorf("%s is not set", name))
	}
	return value
}

func signedToken(keyID, issuerID, privateKeyBase64 string) (string, error) {
	key, err := parsePrivateKey(privateKeyBase64)
	if err != nil {
		return "", err
	}
	now := time.Now().Unix()
	header, _ := json.Marshal(map[string]string{"alg": "ES256", "kid": keyID, "typ": "JWT"})
	claims, _ := json.Marshal(map[string]any{"iss": issuerID, "iat": now, "exp": now + 600, "aud": "appstoreconnect-v1"})
	unsigned := encode(header) + "." + encode(claims)
	digest := sha256.Sum256([]byte(unsigned))
	r, s, err := ecdsa.Sign(rand.Reader, key, digest[:])
	if err != nil {
		return "", err
	}
	signature := make([]byte, 64)
	r.FillBytes(signature[:32])
	s.FillBytes(signature[32:])
	return unsigned + "." + encode(signature), nil
}

func parsePrivateKey(privateKeyBase64 string) (*ecdsa.PrivateKey, error) {
	pemBytes, err := base64.StdEncoding.DecodeString(privateKeyBase64)
	if err != nil {
		return nil, fmt.Errorf("the App Store Connect key is not valid base64: %w", err)
	}
	block, _ := pem.Decode(pemBytes)
	if block == nil {
		return nil, fmt.Errorf("the App Store Connect key is not a PEM file")
	}
	parsed, err := x509.ParsePKCS8PrivateKey(block.Bytes)
	if err != nil {
		return nil, err
	}
	key, ok := parsed.(*ecdsa.PrivateKey)
	if !ok {
		return nil, fmt.Errorf("the App Store Connect key is not an EC key")
	}
	return key, nil
}

func encode(data []byte) string {
	return base64.RawURLEncoding.EncodeToString(data)
}

func isRegistered(token, identifier string) (bool, error) {
	query := url.Values{"filter[identifier]": {identifier}}
	response, err := send(http.MethodGet, bundleIDsEndpoint+"?"+query.Encode(), token, nil)
	if err != nil {
		return false, err
	}
	var list bundleIDList
	if err := json.Unmarshal(response, &list); err != nil {
		return false, err
	}
	for _, item := range list.Data {
		if item.Attributes.Identifier == identifier {
			return true, nil
		}
	}
	return false, nil
}

func register(token, identifier, name string) error {
	body, _ := json.Marshal(map[string]any{
		"data": map[string]any{
			"type": "bundleIds",
			"attributes": map[string]string{
				"identifier": identifier,
				"name":       name,
				"platform":   "MAC_OS",
			},
		},
	})
	_, err := send(http.MethodPost, bundleIDsEndpoint, token, body)
	return err
}

func send(method, endpoint, token string, body []byte) ([]byte, error) {
	request, err := http.NewRequest(method, endpoint, bytes.NewReader(body))
	if err != nil {
		return nil, err
	}
	request.Header.Set("Authorization", "Bearer "+token)
	request.Header.Set("Content-Type", "application/json")
	client := http.Client{Timeout: 30 * time.Second}
	response, err := client.Do(request)
	if err != nil {
		return nil, err
	}
	defer response.Body.Close()
	payload, err := io.ReadAll(response.Body)
	if err != nil {
		return nil, err
	}
	if response.StatusCode >= 400 {
		return nil, fmt.Errorf("App Store Connect returned %s: %s", response.Status, payload)
	}
	return payload, nil
}
