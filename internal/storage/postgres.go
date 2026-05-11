package storage

import (
	"context"
	"database/sql"
	"errors"
	"os"
	"time"

	"valve/internal/credentials"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

var ErrNotFound = errors.New("not found")

type PostgresStore struct {
	pool *pgxpool.Pool
}

func NewPostgresStore(ctx context.Context, databaseURL string) (*PostgresStore, error) {
	pool, err := pgxpool.New(ctx, databaseURL)
	if err != nil {
		return nil, err
	}
	return &PostgresStore{pool: pool}, nil
}

func (s *PostgresStore) Close() {
	s.pool.Close()
}

func (s *PostgresStore) Ping(ctx context.Context) error {
	return s.pool.Ping(ctx)
}

func (s *PostgresStore) ApplySchemaFromFile(ctx context.Context, schemaPath string) error {
	schema, err := os.ReadFile(schemaPath)
	if err != nil {
		return err
	}
	_, err = s.pool.Exec(ctx, string(schema))
	return err
}

func (s *PostgresStore) CreateCredential(ctx context.Context, rec credentials.CredentialRecord, hmacSecretEncrypted []byte, hmacSecretHash string) error {
	_, err := s.pool.Exec(ctx, `
		INSERT INTO valve_credentials (
			credential_id, tenant_id, install_id, actor_user_id, app_bundle_id, app_version, app_build, platform,
			credential_mode, public_key_base64, hmac_secret_encrypted, hmac_secret_hash, status, replaced_by_credential_id, device_label
		) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15)
	`,
		rec.CredentialID, rec.TenantID, rec.InstallID, nullableString(rec.ActorUserID), rec.AppBundleID, nullableString(rec.AppVersion), nullableString(rec.AppBuild), rec.Platform,
		rec.CredentialMode, nullableString(rec.PublicKey), nullableBytes(hmacSecretEncrypted), nullableString(hmacSecretHash), rec.Status, nullableString(rec.ReplacedByCredentialID), nullableString(rec.DeviceLabel),
	)
	return err
}

func (s *PostgresStore) GetCredential(ctx context.Context, credentialID string) (credentials.CredentialRecord, []byte, string, error) {
	row := s.pool.QueryRow(ctx, `
		SELECT credential_id, tenant_id, install_id, actor_user_id, app_bundle_id, app_version, app_build, platform,
		       credential_mode, public_key_base64, hmac_secret_encrypted, hmac_secret_hash, status,
			   replaced_by_credential_id, device_label, created_at, revoked_at, rotated_at, last_seen_at
		FROM valve_credentials
		WHERE credential_id = $1
	`, credentialID)

	rec, hmacEncrypted, hmacHash, err := scanCredential(row)
	if err != nil {
		return credentials.CredentialRecord{}, nil, "", err
	}
	return rec, hmacEncrypted, hmacHash, nil
}

func (s *PostgresStore) ListCredentials(ctx context.Context, tenantID string, installID string) ([]credentials.CredentialRecord, error) {
	rows, err := s.pool.Query(ctx, `
		SELECT credential_id, tenant_id, install_id, actor_user_id, app_bundle_id, app_version, app_build, platform,
		       credential_mode, public_key_base64, hmac_secret_encrypted, hmac_secret_hash, status,
			   replaced_by_credential_id, device_label, created_at, revoked_at, rotated_at, last_seen_at
		FROM valve_credentials
		WHERE tenant_id = $1 AND install_id = $2
		ORDER BY created_at DESC
	`, tenantID, installID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	out := make([]credentials.CredentialRecord, 0)
	for rows.Next() {
		rec, _, _, err := scanCredential(rows)
		if err != nil {
			return nil, err
		}
		out = append(out, rec)
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}
	return out, nil
}

func (s *PostgresStore) RevokeCredential(ctx context.Context, tenantID string, credentialID string) (*time.Time, error) {
	row := s.pool.QueryRow(ctx, `
		UPDATE valve_credentials
		SET status = 'revoked', revoked_at = now()
		WHERE tenant_id = $1 AND credential_id = $2 AND status = 'active'
		RETURNING revoked_at
	`, tenantID, credentialID)
	var revokedAt time.Time
	if err := row.Scan(&revokedAt); err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, ErrNotFound
		}
		return nil, err
	}
	return &revokedAt, nil
}

func (s *PostgresStore) RotateCredential(ctx context.Context, oldCredentialID string, oldTenantID string, oldInstallID string, replacement credentials.CredentialRecord, hmacSecretEncrypted []byte, hmacSecretHash string) error {
	tx, err := s.pool.BeginTx(ctx, pgx.TxOptions{})
	if err != nil {
		return err
	}
	defer tx.Rollback(ctx)

	row := tx.QueryRow(ctx, `
		UPDATE valve_credentials
		SET status = 'rotated', rotated_at = now(), replaced_by_credential_id = $1
		WHERE credential_id = $2 AND tenant_id = $3 AND install_id = $4 AND status = 'active'
		RETURNING credential_id
	`, replacement.CredentialID, oldCredentialID, oldTenantID, oldInstallID)
	var updatedID string
	if err := row.Scan(&updatedID); err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return ErrNotFound
		}
		return err
	}

	_, err = tx.Exec(ctx, `
		INSERT INTO valve_credentials (
			credential_id, tenant_id, install_id, actor_user_id, app_bundle_id, app_version, app_build, platform,
			credential_mode, public_key_base64, hmac_secret_encrypted, hmac_secret_hash, status, replaced_by_credential_id, device_label
		) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15)
	`,
		replacement.CredentialID, replacement.TenantID, replacement.InstallID, nullableString(replacement.ActorUserID),
		replacement.AppBundleID, nullableString(replacement.AppVersion), nullableString(replacement.AppBuild), replacement.Platform,
		replacement.CredentialMode, nullableString(replacement.PublicKey), nullableBytes(hmacSecretEncrypted), nullableString(hmacSecretHash),
		replacement.Status, nullableString(replacement.ReplacedByCredentialID), nullableString(replacement.DeviceLabel),
	)
	if err != nil {
		return err
	}

	return tx.Commit(ctx)
}

func (s *PostgresStore) WriteAudit(ctx context.Context, audit credentials.AuditEntry) error {
	metadataJSON := audit.MetadataJSON
	if metadataJSON == "" {
		metadataJSON = "{}"
	}
	_, err := s.pool.Exec(ctx, `
		INSERT INTO valve_audit_log(actor_user_id, tenant_id, install_id, credential_id, action, reason, metadata)
		VALUES($1,$2,$3,$4,$5,$6,$7::jsonb)
	`,
		nullableString(audit.ActorUserID), audit.TenantID, nullableString(audit.InstallID), nullableString(audit.CredentialID), audit.Action, nullableString(audit.Reason), metadataJSON,
	)
	return err
}

func (s *PostgresStore) LookupVerification(ctx context.Context, credentialID string) (credentials.VerificationResponse, error) {
	row := s.pool.QueryRow(ctx, `
		SELECT credential_id, tenant_id, install_id, app_bundle_id, credential_mode, public_key_base64, status, revoked_at
		FROM valve_credentials
		WHERE credential_id = $1
	`, credentialID)
	var resp credentials.VerificationResponse
	var publicKey sql.NullString
	var revokedAt sql.NullTime
	if err := row.Scan(
		&resp.CredentialID,
		&resp.TenantID,
		&resp.InstallID,
		&resp.AppBundleID,
		&resp.CredentialMode,
		&publicKey,
		&resp.Status,
		&revokedAt,
	); err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return credentials.VerificationResponse{}, ErrNotFound
		}
		return credentials.VerificationResponse{}, err
	}
	if publicKey.Valid {
		resp.PublicKey = publicKey.String
	}
	if revokedAt.Valid {
		ts := revokedAt.Time
		resp.RevokedAt = &ts
	}
	return resp, nil
}

func scanCredential(row scanner) (credentials.CredentialRecord, []byte, string, error) {
	var rec credentials.CredentialRecord
	var actorUserID sql.NullString
	var appVersion sql.NullString
	var appBuild sql.NullString
	var publicKey sql.NullString
	var hmacEncrypted []byte
	var hmacHash sql.NullString
	var replacedBy sql.NullString
	var deviceLabel sql.NullString
	var revokedAt sql.NullTime
	var rotatedAt sql.NullTime
	var lastSeenAt sql.NullTime

	err := row.Scan(
		&rec.CredentialID,
		&rec.TenantID,
		&rec.InstallID,
		&actorUserID,
		&rec.AppBundleID,
		&appVersion,
		&appBuild,
		&rec.Platform,
		&rec.CredentialMode,
		&publicKey,
		&hmacEncrypted,
		&hmacHash,
		&rec.Status,
		&replacedBy,
		&deviceLabel,
		&rec.CreatedAt,
		&revokedAt,
		&rotatedAt,
		&lastSeenAt,
	)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return credentials.CredentialRecord{}, nil, "", ErrNotFound
		}
		return credentials.CredentialRecord{}, nil, "", err
	}
	if actorUserID.Valid {
		rec.ActorUserID = actorUserID.String
	}
	if appVersion.Valid {
		rec.AppVersion = appVersion.String
	}
	if appBuild.Valid {
		rec.AppBuild = appBuild.String
	}
	if publicKey.Valid {
		rec.PublicKey = publicKey.String
	}
	if replacedBy.Valid {
		rec.ReplacedByCredentialID = replacedBy.String
	}
	if deviceLabel.Valid {
		rec.DeviceLabel = deviceLabel.String
	}
	if revokedAt.Valid {
		ts := revokedAt.Time
		rec.RevokedAt = &ts
	}
	if rotatedAt.Valid {
		ts := rotatedAt.Time
		rec.RotatedAt = &ts
	}
	if lastSeenAt.Valid {
		ts := lastSeenAt.Time
		rec.LastSeenAt = &ts
	}
	return rec, hmacEncrypted, hmacHash.String, nil
}

type scanner interface {
	Scan(dest ...any) error
}

func nullableString(v string) any {
	if v == "" {
		return nil
	}
	return v
}

func nullableBytes(v []byte) any {
	if len(v) == 0 {
		return nil
	}
	return v
}
