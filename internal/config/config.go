package config

import (
	"errors"
	"os"
	"strconv"
	"strings"
)

type Config struct {
	Addr                       string
	DatabaseURL                string
	UploadEndpoint             string
	DevAuthAllowAll            bool
	HMACModeEnabled            bool
	ServiceAuthKey             string
	UploadTargetTTLSeconds     int
	UploadTargetRoutingVersion string
	UploadTargetAllowedHosts   []string
	UploadTargetTenantRoutes   map[string]string
}

// #R001: Resolve environment-backed config values with defaults for optional fields.
func Load() (Config, error) {
	cfg := Config{
		Addr:                       getEnvOrDefault("VALVE_ADDR", ":8090"),
		DatabaseURL:                os.Getenv("VALVE_DATABASE_URL"),
		UploadEndpoint:             os.Getenv("VALVE_UPLOAD_ENDPOINT"),
		DevAuthAllowAll:            parseBoolOrDefault("VALVE_DEV_AUTH_ALLOW_ALL", false),
		HMACModeEnabled:            parseBoolOrDefault("VALVE_HMAC_MODE_ENABLED", false),
		ServiceAuthKey:             os.Getenv("VALVE_SERVICE_AUTH_KEY"),
		UploadTargetTTLSeconds:     parseIntOrDefault("VALVE_UPLOAD_TARGET_TTL_SECONDS", 300),
		UploadTargetRoutingVersion: getEnvOrDefault("VALVE_UPLOAD_TARGET_ROUTING_VERSION", "v1"),
		UploadTargetAllowedHosts:   parseCSV(os.Getenv("VALVE_UPLOAD_TARGET_ALLOWED_HOSTS")),
		UploadTargetTenantRoutes:   parseTenantRoutes(os.Getenv("VALVE_UPLOAD_TARGET_TENANT_ROUTES")),
	}

	// #R005: Enforce required database and upload endpoint settings before boot.
	if cfg.DatabaseURL == "" {
		return Config{}, errors.New("VALVE_DATABASE_URL is required")
	}
	if cfg.UploadEndpoint == "" {
		return Config{}, errors.New("VALVE_UPLOAD_ENDPOINT is required")
	}
	if cfg.UploadTargetTTLSeconds <= 0 {
		return Config{}, errors.New("VALVE_UPLOAD_TARGET_TTL_SECONDS must be > 0")
	}
	if cfg.UploadTargetRoutingVersion == "" {
		return Config{}, errors.New("VALVE_UPLOAD_TARGET_ROUTING_VERSION is required")
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

func parseIntOrDefault(key string, fallback int) int {
	value := os.Getenv(key)
	if value == "" {
		return fallback
	}
	parsed, err := strconv.Atoi(value)
	if err != nil {
		return fallback
	}
	return parsed
}

func parseCSV(value string) []string {
	if value == "" {
		return nil
	}
	parts := strings.Split(value, ",")
	out := make([]string, 0, len(parts))
	for _, part := range parts {
		trimmed := strings.TrimSpace(part)
		if trimmed == "" {
			continue
		}
		out = append(out, trimmed)
	}
	return out
}

func parseTenantRoutes(value string) map[string]string {
	out := map[string]string{}
	for _, entry := range parseCSV(value) {
		parts := strings.SplitN(entry, "=", 2)
		if len(parts) != 2 {
			continue
		}
		tenantID := strings.TrimSpace(parts[0])
		route := strings.TrimSpace(parts[1])
		if tenantID == "" || route == "" {
			continue
		}
		out[tenantID] = route
	}
	return out
}
