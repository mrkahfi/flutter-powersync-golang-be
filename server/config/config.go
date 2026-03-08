package config

import (
	"encoding/base64"
	"fmt"
	"os"
	"strings"
)

// Config holds all application configuration.
type Config struct {
	Port               string
	PowerSyncURL       string
	DatabaseURI        string
	PrivateKeyPEM      []byte
	PublicKeyPEM       []byte
	KeyID              string
	DevMode            bool
}

// Load reads configuration from environment variables.
// Call after loading .env (e.g. via github.com/joho/godotenv).
func Load() (*Config, error) {
	cfg := &Config{
		Port:         getEnvOrDefault("PORT", "8080"),
		PowerSyncURL: mustEnv("POWERSYNC_URL"),
		DatabaseURI:  getEnvOrDefault("DATABASE_URI", ""),
		KeyID:        getEnvOrDefault("POWERSYNC_KEY_ID", "powersync-key-1"),
		DevMode:      strings.EqualFold(os.Getenv("DEV_MODE"), "true"),
	}

	if !cfg.DevMode {
		privB64 := mustEnv("POWERSYNC_PRIVATE_KEY_BASE64")
		pubB64 := mustEnv("POWERSYNC_PUBLIC_KEY_BASE64")

		privPEM, err := base64.StdEncoding.DecodeString(privB64)
		if err != nil {
			return nil, fmt.Errorf("config: decode private key: %w", err)
		}
		pubPEM, err := base64.StdEncoding.DecodeString(pubB64)
		if err != nil {
			return nil, fmt.Errorf("config: decode public key: %w", err)
		}
		cfg.PrivateKeyPEM = privPEM
		cfg.PublicKeyPEM = pubPEM
	}

	return cfg, nil
}

func mustEnv(key string) string {
	v := os.Getenv(key)
	if v == "" {
		panic(fmt.Sprintf("required environment variable %q is not set", key))
	}
	return v
}

func getEnvOrDefault(key, def string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return def
}
