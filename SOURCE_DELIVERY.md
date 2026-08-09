# GenericIM Source Delivery

This file is the handoff entry point for a customer source package.

## Included

- Flutter client for Android, iOS, Web, Windows and macOS.
- Vue H5/PWA client.
- Go API, database models, migrations and WebSocket services.
- Operations admin and customer-service admin frontends.
- Docker, reverse-proxy, build and deployment scripts.
- Architecture, configuration, security and operations documentation.

## Excluded

The delivery package must not contain:

- Git history or private worktree metadata.
- `node_modules`, `.dart_tool`, `build`, `dist`, caches or test artifacts.
- `.env` files containing values, signing files or cloud credentials.
- Database dumps, user uploads, logs, crash dumps or release binaries.
- `google-services.json`, `GoogleService-Info.plist`, keystores or private keys.

## Start Here

1. Read `README.md`.
2. Read `NOTICE.md` and add the recipient's own legal notice when required.
3. Copy the example configuration and fill deployment-specific values.
4. Read `docs/CONFIGURATION.md` before starting services.
5. Start local dependencies with `docker compose up -d --build`.
6. Run `scripts/verify-source-delivery.ps1`.
7. Run the backend, H5 and Flutter checks listed in `docs/OPERATIONS.md`.

## Build Reproducibility

Record the following values in the private delivery manifest:

- Customer delivery identifier.
- Git commit or source snapshot identifier.
- Go, Flutter, Dart, Node and package-manager versions.
- Database migration version.
- Release artifact SHA256 values.
- Storage, push, RTC and payment provider configuration fingerprints.

The customer package should be generated from a reviewed source snapshot. If
the current developer worktree is intentionally used, record its baseline
commit, review every local change and run the delivery verifier against the
staged package before handoff.

## Security Boundary

The source package contains no production secrets or project-owned production
domains. Reserved example domains may remain in deployment examples and must
be replaced with customer-owned domains before deployment. The customer is responsible for generating deployment
secrets, restricting database and Redis network access, configuring HTTPS and
setting production CORS/WebSocket origins.

Third-party license and attribution files are retained for compliance and must
not be treated as product branding.
