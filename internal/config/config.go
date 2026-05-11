package config

import (
	"errors"
	"os"
	"strconv"
)

type Config struct {
	Addr            string
	DatabaseURL     string
	UploadEndpoint  string
	DevAuthAllowAll bool
	HMACModeEnabled bool
	ServiceAuthKey  string
}

// #R001: Resolve environment-backed config values with defaults for optional fields.
func Load() (Config, error) {
	cfg := Config{
		Addr:            getEnvOrDefault("VALVE_ADDR", ":8090"),
		DatabaseURL:     os.Getenv("VALVE_DATABASE_URL"),
		UploadEndpoint:  os.Getenv("VALVE_UPLOAD_ENDPOINT"),
		DevAuthAllowAll: parseBoolOrDefault("VALVE_DEV_AUTH_ALLOW_ALL", false),
		HMACModeEnabled: parseBoolOrDefault("VALVE_HMAC_MODE_ENABLED", false),
		ServiceAuthKey:  os.Getenv("VALVE_SERVICE_AUTH_KEY"),
	}

	// #R005: Enforce required database and upload endpoint settings before boot.
	if cfg.DatabaseURL == "" {
		return Config{}, errors.New("VALVE_DATABASE_URL is required")
	}
	if cfg.UploadEndpoint == "" {
		return Config{}, errors.New("VALVE_UPLOAD_ENDPOINT is required")
	}
	return cfg, nil
}

func getEnvOrDefault(key string, fallback string) string {
	value := os.Getenv(key)
	if value == "" {
		return fallback
	}
	return value
}

// #R010: Parse booleans safely and fall back when env values are invalid.
func parseBoolOrDefault(key string, fallback bool) bool {
	value := os.Getenv(key)
	if value == "" {
		return fallback
	}
	parsed, err := strconv.ParseBool(value)
	if err != nil {
		return fallback
	}
	return parsed
}
