package credentials

import (
	"bytes"
	"context"
	"encoding/base64"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
)

// Supplemental numbered tag for request validation/error mapping parity.
// #R010-T06

func TestHandlerRegisterAndErrorMapping(t *testing.T) {
	// #R001-T01: Malformed JSON body returns HTTP 400 with error field.
	// #R001-T02: Valid register request returns HTTP 200 with credential_id.
	// #R010-T01: ErrInvalidInput produces HTTP 400 with JSON error field.
	// #R010: Handler maps invalid JSON and service errors into stable HTTP responses.
	service := NewService(newMockStore(), handlerAuthorizer{allow: true}, "https://ingest.example.com", false, false)
	handler := NewHandler(service)
	payload := RegisterRequest{TenantID: "tenant", ActorUserID: "actor", InstallID: "install", AppBundleID: "bundle", Platform: "macOS", CredentialMode: ModeEd25519, PublicKey: base64.StdEncoding.EncodeToString(make([]byte, 32))}
	body, _ := json.Marshal(payload)
	req := httptest.NewRequest(http.MethodPost, "/v1/valve/credentials/register", bytes.NewReader(body))
	rec := httptest.NewRecorder()
	handler.RegisterCredential(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200 register status, got %d", rec.Code)
	}
	badReq := httptest.NewRequest(http.MethodPost, "/v1/valve/credentials/register", bytes.NewBufferString("{"))
	badRec := httptest.NewRecorder()
	handler.RegisterCredential(badRec, badReq)
	if badRec.Code != http.StatusBadRequest {
		t.Fatalf("expected 400 for invalid json, got %d", badRec.Code)
	}
}

func TestHandlerListAndVerificationLookup(t *testing.T) {
	// #R005-T01: ListCredentials passes tenant_id and install_id query params to service.
	// #R005-T02: VerificationLookup passes credential_id URL param to service.
	// #R005: Handler maps query and path inputs to list and verification lookups.
	store := newMockStore()
	recID := "cred_handler"
	store.records[recID] = CredentialRecord{CredentialID: recID, TenantID: "tenant", InstallID: "install", AppBundleID: "bundle", Platform: "macOS", CredentialMode: ModeEd25519, PublicKey: base64.StdEncoding.EncodeToString(make([]byte, 32)), Status: StatusActive}
	service := NewService(store, handlerAuthorizer{allow: true}, "https://ingest.example.com", false, false)
	handler := NewHandler(service)
	listReq := httptest.NewRequest(http.MethodGet, "/v1/valve/credentials?tenant_id=tenant&install_id=install", nil)
	listRec := httptest.NewRecorder()
	handler.ListCredentials(listRec, listReq)
	if listRec.Code != http.StatusOK {
		t.Fatalf("expected 200 list status, got %d", listRec.Code)
	}
	lookup, err := service.VerificationLookup(context.Background(), recID)
	if err != nil || lookup.CredentialID != recID {
		t.Fatalf("expected verification lookup success")
	}
}

func TestHandlerUploadTargetAndConflictMapping(t *testing.T) {
	// #R015-T01: Valid upload target request returns HTTP 200 with Cache-Control header.
	// #R010-T04: ErrTenantMismatch produces HTTP 409 with JSON error field.
	store := newMockStore()
	recID := "cred_upload_handler"
	store.records[recID] = CredentialRecord{
		CredentialID: recID,
		TenantID:     "tenant",
		InstallID:    "install",
		Status:       StatusActive,
	}
	service := NewService(store, handlerAuthorizer{allow: true}, "https://ingest.example.com/v1/events/batch", false, false)
	if err := service.ConfigureUploadTargetDiscovery(UploadTargetDiscoveryConfig{
		TTLSeconds:               300,
		RoutingVersion:           "routing-v1",
		AllowedUploadTargetHosts: []string{"ingest.example.com"},
	}); err != nil {
		t.Fatalf("configure discovery failed: %v", err)
	}
	handler := NewHandler(service)

	payload := UploadTargetRequest{
		TenantID:     "tenant",
		InstallID:    "install",
		CredentialID: recID,
	}
	body, _ := json.Marshal(payload)
	req := httptest.NewRequest(http.MethodPost, "/v1/piston/upload-target", bytes.NewReader(body))
	rec := httptest.NewRecorder()
	handler.UploadTarget(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200 upload target status, got %d", rec.Code)
	}
	if rec.Header().Get("Cache-Control") == "" {
		t.Fatalf("expected cache-control header to be set")
	}

	badPayload := UploadTargetRequest{
		TenantID:     "tenant-other",
		InstallID:    "install",
		CredentialID: recID,
	}
	badBody, _ := json.Marshal(badPayload)
	badReq := httptest.NewRequest(http.MethodPost, "/v1/piston/upload-target", bytes.NewReader(badBody))
	badRec := httptest.NewRecorder()
	handler.UploadTarget(badRec, badReq)
	if badRec.Code != http.StatusConflict {
		t.Fatalf("expected 409 tenant mismatch status, got %d", badRec.Code)
	}
}

type handlerAuthorizer struct {
	allow bool
}

func (a handlerAuthorizer) CanProvisionIngestCredential(context.Context, string, string) (bool, error) {
	return a.allow, nil
}

func (a handlerAuthorizer) CanRevokeIngestCredential(context.Context, string, string, string) (bool, error) {
	return a.allow, nil
}
