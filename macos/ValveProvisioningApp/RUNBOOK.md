# Valve Provisioning UI Runbook

## Launch
- `cd macos/ValveProvisioningApp`
- `swift run ValveProvisioningApp`

## Required Environment Variables
- `VALVE_BASE_URL` (example: `http://localhost:8080`)
- `VALVE_TENANT_ID`
- `VALVE_INSTALL_ID`
- `VALVE_ACTOR_USER_ID`

## Provisioning
- Open **Provision** tab.
- Review tenant/install/operator fields.
- Click **Provision Credential**.
- Save the returned `credential_id` from status output.

## Deprovisioning
- Open **Deprovision** tab.
- Enter `credential_id` and reason.
- Click **Revoke Credential**.

## Rotation
- Open **Rotate** tab.
- Enter old credential id and metadata.
- Click **Rotate Credential**.

## Inventory
- Open **Inventory** tab.
- Verify tenant/install filters.
- Click **Refresh** to load lifecycle status.

## Notes
- Private keys and optional HMAC secrets are stored in macOS Keychain.
- Local action audit logs are appended to `~/Library/Application Support/ValveProvisioningApp/audit.jsonl`.
