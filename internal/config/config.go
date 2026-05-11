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

func Load() (Config, error) {
	cfg := Config{
		Addr:            getEnvOrDefault("VALVE_ADDR", ":8090"),
		DatabaseURL:     os.Getenv("VALVE_DATABASE_URL"),
		UploadEndpoint:  os.Getenv("VALVE_UPLOAD_ENDPOINT"),
		DevAuthAllowAll: parseBoolOrDefault("VALVE_DEV_AUTH_ALLOW_ALL", false),
		HMACModeEnabled: parseBoolOrDefault("VALVE_HMAC_MODE_ENABLED", false),
		ServiceAuthKey:  os.Getenv("VALVE_SERVICE_AUTH_KEY"),
	}

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
