package appstore

import (
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/sha256"
	"crypto/x509"
	"encoding/base64"
	"encoding/json"
	"encoding/pem"
	"math/big"
	"reflect"
	"strings"
	"testing"
)

func TestDisplayName(t *testing.T) {
	cases := map[string]string{
		"dev.adrian.ishare":              "ishare",
		"dev.adrian.ISHARE":              "ishare",
		"dev.adrian.ishare.sharemenuext": "ishare sharemenuext",
	}
	for identifier, want := range cases {
		if got := DisplayName("ishare", identifier); got != want {
			t.Errorf("DisplayName(%q) = %q, want %q", identifier, got, want)
		}
	}
}

func TestParseIdentifiers(t *testing.T) {
	got := ParseIdentifiers(" dev.adrian.ishare, ,dev.adrian.ishare.sharemenuext,")
	want := []string{"dev.adrian.ishare", "dev.adrian.ishare.sharemenuext"}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("got %v", got)
	}
}

func TestCredentialsFromEnvironmentReportsMissingValues(t *testing.T) {
	t.Setenv("KEY_ID", "key")
	t.Setenv("ISSUER_ID", "")
	t.Setenv("PRIVATE_KEY_BASE64", "")
	_, err := CredentialsFromEnvironment()
	if err == nil || !strings.Contains(err.Error(), "ISSUER_ID, PRIVATE_KEY_BASE64") {
		t.Fatalf("unexpected error %v", err)
	}
}

func TestSignedTokenIsAValidES256JWT(t *testing.T) {
	key, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	der, err := x509.MarshalPKCS8PrivateKey(key)
	if err != nil {
		t.Fatal(err)
	}
	encodedKey := base64.StdEncoding.EncodeToString(pem.EncodeToMemory(&pem.Block{Type: "PRIVATE KEY", Bytes: der}))
	token, err := signedToken("KEY123", "issuer", encodedKey)
	if err != nil {
		t.Fatal(err)
	}
	parts := strings.Split(token, ".")
	if len(parts) != 3 {
		t.Fatalf("token has %d parts", len(parts))
	}
	var header map[string]string
	decodeSegment(t, parts[0], &header)
	if header["alg"] != "ES256" || header["kid"] != "KEY123" {
		t.Fatalf("unexpected header %v", header)
	}
	var claims map[string]any
	decodeSegment(t, parts[1], &claims)
	if claims["iss"] != "issuer" || claims["aud"] != "appstoreconnect-v1" {
		t.Fatalf("unexpected claims %v", claims)
	}
	signature, err := base64.RawURLEncoding.DecodeString(parts[2])
	if err != nil || len(signature) != 64 {
		t.Fatalf("unexpected signature: %v", err)
	}
	digest := sha256.Sum256([]byte(parts[0] + "." + parts[1]))
	r := new(big.Int).SetBytes(signature[:32])
	s := new(big.Int).SetBytes(signature[32:])
	if !ecdsa.Verify(&key.PublicKey, digest[:], r, s) {
		t.Fatal("the signature does not verify")
	}
}

func TestSignedTokenRejectsInvalidKeys(t *testing.T) {
	for _, candidate := range []string{"not base64!", base64.StdEncoding.EncodeToString([]byte("not pem"))} {
		if _, err := signedToken("key", "issuer", candidate); err == nil {
			t.Errorf("expected %q to be rejected", candidate)
		}
	}
}

func decodeSegment(t *testing.T, segment string, into any) {
	t.Helper()
	data, err := base64.RawURLEncoding.DecodeString(segment)
	if err != nil {
		t.Fatal(err)
	}
	if err := json.Unmarshal(data, into); err != nil {
		t.Fatal(err)
	}
}
