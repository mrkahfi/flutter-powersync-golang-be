// Package auth handles PowerSync JWT generation and JWKS exposure.
//
// PowerSync requires:
//   - GET /api/auth/token  → returns a signed JWT for the current user
//   - GET /api/auth/keys   → returns the JWKS so PowerSync can verify the JWTs
//
// JWT requirements (from PowerSync docs):
//   - Signed with RS256 (we use RS256 here).
//   - `kid` header must match the key in the JWKS.
//   - `aud` must match your PowerSync instance URL.
//   - `sub` must be the user ID.
//   - `iat` + `exp` must be present; difference ≤ 86 400 s (24 h).
package auth

import (
	"crypto"
	"crypto/rand"
	"crypto/rsa"
	"crypto/sha256"
	"crypto/x509"
	"encoding/base64"
	"encoding/json"
	"encoding/pem"
	"fmt"
	"math/big"
	"time"

	"powersync-backend/config"
)

// Manager handles key material and JWT minting.
type Manager struct {
	cfg        *config.Config
	privateKey *rsa.PrivateKey
}

// New creates an auth.Manager.
// In DevMode a throw-away RSA key is generated so you can test without real keys.
func New(cfg *config.Config) (*Manager, error) {
	m := &Manager{cfg: cfg}

	if cfg.DevMode {
		key, err := rsa.GenerateKey(rand.Reader, 2048)
		if err != nil {
			return nil, fmt.Errorf("auth: generate dev key: %w", err)
		}
		m.privateKey = key
		return m, nil
	}

	block, _ := pem.Decode(cfg.PrivateKeyPEM)
	if block == nil {
		return nil, fmt.Errorf("auth: failed to decode private key PEM")
	}
	key, err := x509.ParsePKCS1PrivateKey(block.Bytes)
	if err != nil {
		// Try PKCS8
		parsed, err2 := x509.ParsePKCS8PrivateKey(block.Bytes)
		if err2 != nil {
			return nil, fmt.Errorf("auth: parse private key: PKCS1: %v, PKCS8: %v", err, err2)
		}
		rsaKey, ok := parsed.(*rsa.PrivateKey)
		if !ok {
			return nil, fmt.Errorf("auth: private key is not RSA")
		}
		key = rsaKey
	}
	m.privateKey = key
	return m, nil
}

// MintToken produces a signed RS256 JWT for the given user ID.
// userID becomes the `sub` claim.
func (m *Manager) MintToken(userID string) (string, error) {
	now := time.Now()
	exp := now.Add(60 * time.Minute)

	// Header
	headerJSON, _ := json.Marshal(map[string]string{
		"alg": "RS256",
		"typ": "JWT",
		"kid": m.cfg.KeyID,
	})

	// Payload
	payloadJSON, _ := json.Marshal(map[string]interface{}{
		"sub": userID,
		"aud": m.cfg.PowerSyncURL,
		"iat": now.Unix(),
		"exp": exp.Unix(),
	})

	header := base64.RawURLEncoding.EncodeToString(headerJSON)
	payload := base64.RawURLEncoding.EncodeToString(payloadJSON)
	signingInput := header + "." + payload

	// Sign with RS256
	h := sha256.Sum256([]byte(signingInput))
	sig, err := rsa.SignPKCS1v15(rand.Reader, m.privateKey, crypto.SHA256, h[:])
	if err != nil {
		return "", fmt.Errorf("auth: sign token: %w", err)
	}

	return signingInput + "." + base64.RawURLEncoding.EncodeToString(sig), nil
}

// JWKS returns the JSON Web Key Set for the active signing key.
// Expose this at GET /api/auth/keys so PowerSync can verify tokens.
func (m *Manager) JWKS() ([]byte, error) {
	pub := &m.privateKey.PublicKey

	key := map[string]interface{}{
		"kty": "RSA",
		"use": "sig",
		"alg": "RS256",
		"kid": m.cfg.KeyID,
		"n":   base64.RawURLEncoding.EncodeToString(pub.N.Bytes()),
		"e":   base64.RawURLEncoding.EncodeToString(big.NewInt(int64(pub.E)).Bytes()),
	}

	return json.Marshal(map[string]interface{}{
		"keys": []interface{}{key},
	})
}
