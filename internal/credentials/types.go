package credentials

import "time"

// #R001: Canonical credential mode and lifecycle status constants.
const (
	ModeEd25519    = "ed25519"
	ModeHMACSHA256 = "hmac_sha256"

	StatusActive  = "active"
	StatusRevoked = "revoked"
	StatusRotated = "rotated"
)

// #R005: API request and response payload models for credential operations.
type RegisterRequest struct {
	TenantID       string `json:"tenant_id"`
	ActorUserID    string `json:"actor_user_id"`
	InstallID      string `json:"install_id"`
	AppBundleID    string `json:"app_bundle_id"`
	AppVersion     string `json:"app_version"`
	AppBuild       string `json:"app_build"`
	Platform       string `json:"platform"`
	DeviceLabel    string `json:"device_label"`
	CredentialMode string `json:"credential_mode"`
	PublicKey      string `json:"public_key"`
}

type RegisterResponse struct {
	CredentialID     string `json:"credential_id"`
	TenantScope      string `json:"tenant_scope"`
	InstallID        string `json:"install_id"`
	UploadEndpoint   string `json:"upload_endpoint"`
	SigningAlgorithm string `json:"signing_algorithm"`
	Secret           string `json:"secret,omitempty"`
	Status           string `json:"status"`
}

type RevokeRequest struct {
	TenantID     string `json:"tenant_id"`
	ActorUserID  string `json:"actor_user_id"`
	CredentialID string `json:"credential_id"`
	Reason       string `json:"reason"`
}

type RevokeResponse struct {
	CredentialID string     `json:"credential_id"`
	Status       string     `json:"status"`
	RevokedAt    *time.Time `json:"revoked_at"`
}

type RotateRequest struct {
	TenantID        string `json:"tenant_id"`
	ActorUserID     string `json:"actor_user_id"`
	OldCredentialID string `json:"old_credential_id"`
	InstallID       string `json:"install_id"`
	CredentialMode  string `json:"credential_mode"`
	NewPublicKey    string `json:"new_public_key"`
	AppVersion      string `json:"app_version"`
	AppBuild        string `json:"app_build"`
	DeviceLabel     string `json:"device_label"`
}

type RotateResponse struct {
	OldCredentialID  string `json:"old_credential_id"`
	OldStatus        string `json:"old_status"`
	NewCredentialID  string `json:"new_credential_id"`
	TenantScope      string `json:"tenant_scope"`
	InstallID        string `json:"install_id"`
	SigningAlgorithm string `json:"signing_algorithm"`
	Status           string `json:"status"`
	Secret           string `json:"secret,omitempty"`
}

// #R010: Persisted credential and audit model definitions across storage boundaries.
type CredentialRecord struct {
	CredentialID           string     `json:"credential_id"`
	TenantID               string     `json:"tenant_id"`
	InstallID              string     `json:"install_id"`
	ActorUserID            string     `json:"actor_user_id,omitempty"`
	AppBundleID            string     `json:"app_bundle_id"`
	AppVersion             string     `json:"app_version,omitempty"`
	AppBuild               string     `json:"app_build,omitempty"`
	Platform               string     `json:"platform"`
	CredentialMode         string     `json:"credential_mode"`
	PublicKey              string     `json:"public_key,omitempty"`
	Status                 string     `json:"status"`
	ReplacedByCredentialID string     `json:"replaced_by_credential_id,omitempty"`
	DeviceLabel            string     `json:"device_label,omitempty"`
	CreatedAt              time.Time  `json:"created_at"`
	RevokedAt              *time.Time `json:"revoked_at"`
	RotatedAt              *time.Time `json:"rotated_at"`
	LastSeenAt             *time.Time `json:"last_seen_at"`
}

type ListResponse struct {
	Credentials []CredentialRecord `json:"credentials"`
}

type VerificationResponse struct {
	CredentialID   string     `json:"credential_id"`
	TenantID       string     `json:"tenant_id"`
	InstallID      string     `json:"install_id"`
	AppBundleID    string     `json:"app_bundle_id"`
	CredentialMode string     `json:"credential_mode"`
	PublicKey      string     `json:"public_key,omitempty"`
	Status         string     `json:"status"`
	RevokedAt      *time.Time `json:"revoked_at"`
}

type UploadTargetRequest struct {
	TenantID     string `json:"tenant_id"`
	InstallID    string `json:"install_id"`
	CredentialID string `json:"credential_id"`
}

type UploadTargetResponse struct {
	UploadURL      string    `json:"upload_url"`
	ExpiresAt      time.Time `json:"expires_at"`
	TTLSeconds     int       `json:"ttl_seconds"`
	RoutingVersion string    `json:"routing_version,omitempty"`
}

type AuditEntry struct {
	ActorUserID  string
	TenantID     string
	InstallID    string
	CredentialID string
	Action       string
	Reason       string
	MetadataJSON string
}
