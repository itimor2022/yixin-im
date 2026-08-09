# GenericIM Security Notes

## Application Controls

- Passwords and sensitive credentials must be stored using the existing
  server-side hashing/encryption paths.
- HTTP authentication uses the configured JWT and session revocation controls.
- WebSocket connections require authentication and an allowed Origin.
- Resource ownership is checked before media access, message mutation and
  account operations.
- Uploads are checked by size, extension, MIME, file signature and media
  probing where enabled.

## Deployment Controls

- Put API, MySQL, MongoDB and Redis on private networks.
- Terminate HTTPS at a trusted reverse proxy or load balancer.
- Do not expose Redis, MongoDB or MySQL to the public internet.
- Rotate deployment secrets independently for each environment.
- Keep backups encrypted and test restoration.
- Restrict object-storage credentials to the required bucket and operations.

## Source Delivery Controls

The source package must be scanned before delivery:

- No `.env` files with values.
- No private keys, certificates, signing files or service credentials.
- No database dumps, user uploads or production logs.
- No generated dependency directories or release binaries.

Run `scripts/verify-source-delivery.ps1` from the repository root. This script
is a pre-delivery check, not a substitute for a human security review.

## Legal notices

`NOTICE.md` describes the neutral delivery boundary. Add the recipient's own
legal notice before publication, while retaining all third-party licenses.
