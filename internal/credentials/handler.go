package credentials

import (
	"encoding/json"
	"errors"
	"fmt"
	"net/http"

	"github.com/go-chi/chi/v5"
)

type Handler struct {
	service *Service
}

func NewHandler(service *Service) *Handler {
	return &Handler{service: service}
}

// #R001: Decode register/revoke/rotate requests and dispatch to service layer.
func (h *Handler) RegisterCredential(w http.ResponseWriter, r *http.Request) {
	var req RegisterRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, "invalid request")
		return
	}
	resp, err := h.service.Register(r.Context(), req)
	if err != nil {
		writeServiceError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, resp)
}

func (h *Handler) RevokeCredential(w http.ResponseWriter, r *http.Request) {
	var req RevokeRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, "invalid request")
		return
	}
	resp, err := h.service.Revoke(r.Context(), req)
	if err != nil {
		writeServiceError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, resp)
}

func (h *Handler) RotateCredential(w http.ResponseWriter, r *http.Request) {
	var req RotateRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, "invalid request")
		return
	}
	resp, err := h.service.Rotate(r.Context(), req)
	if err != nil {
		writeServiceError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, resp)
}

// #R005: Map query and URL inputs to list/verification service lookups.
func (h *Handler) ListCredentials(w http.ResponseWriter, r *http.Request) {
	tenantID := r.URL.Query().Get("tenant_id")
	installID := r.URL.Query().Get("install_id")
	resp, err := h.service.List(r.Context(), tenantID, installID)
	if err != nil {
		writeServiceError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, resp)
}

func (h *Handler) VerificationLookup(w http.ResponseWriter, r *http.Request) {
	credentialID := chi.URLParam(r, "credential_id")
	resp, err := h.service.VerificationLookup(r.Context(), credentialID)
	if err != nil {
		writeServiceError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, resp)
}

// #R015: Set Cache-Control header from TTL and dispatch upload target requests.
func (h *Handler) UploadTarget(w http.ResponseWriter, r *http.Request) {
	var req UploadTargetRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, "invalid request")
		return
	}
	resp, err := h.service.UploadTarget(r.Context(), req)
	if err != nil {
		writeServiceError(w, err)
		return
	}
	w.Header().Set("Cache-Control", fmt.Sprintf("private, max-age=%d", resp.TTLSeconds))
	writeJSON(w, http.StatusOK, resp)
}

// #R010: Translate domain errors into stable HTTP response codes.
func writeServiceError(w http.ResponseWriter, err error) {
	switch {
	case errors.Is(err, ErrInvalidInput):
		writeError(w, http.StatusBadRequest, "invalid input")
	case errors.Is(err, ErrUnauthorized):
		writeError(w, http.StatusForbidden, "unauthorized")
	case errors.Is(err, ErrNotFound):
		writeError(w, http.StatusNotFound, "not found")
	case errors.Is(err, ErrTenantMismatch):
		writeError(w, http.StatusConflict, "tenant/account mismatch")
	case errors.Is(err, ErrInvalidState):
		writeError(w, http.StatusConflict, "invalid credential state")
	default:
		writeError(w, http.StatusInternalServerError, "internal server error")
	}
}

func writeError(w http.ResponseWriter, code int, message string) {
	writeJSON(w, code, map[string]string{
		"error": message,
	})
}

func writeJSON(w http.ResponseWriter, code int, payload any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(code)
	_ = json.NewEncoder(w).Encode(payload)
}
