# GenericIM Operations

## Local Validation

```powershell
docker compose up -d --build
docker compose ps
docker compose logs --tail=100 api
pwsh -File scripts/verify-source-delivery.ps1
```

Health endpoints:

- API: `GET /health`
- API prefix: `/api/v1`
- WebSocket: `/api/v1/ws`

## Release Checklist

- Confirm the source snapshot and customer delivery identifier.
- Generate new production secrets.
- Set release mode and HTTPS origins.
- Run database migrations.
- Confirm MySQL, MongoDB, Redis and object storage connectivity.
- Build the backend, H5 and requested Flutter targets.
- Run login, WebSocket, message, media upload and logout smoke tests.
- Record artifact SHA256 values.
- Back up the database before deployment.

## Backups

Back up MySQL, MongoDB, Redis data when persistence is enabled, and object
storage metadata. Keep backups outside the application host and periodically
perform a restore rehearsal.

## Incident Triage

1. Check `/health` and container health.
2. Inspect API logs for request IDs and database/Redis errors.
3. Check database, Redis and object-storage reachability.
4. Check WebSocket reconnect rate and message sequence gaps.
5. Stop only the affected component when possible.
6. Preserve logs and the release manifest before rollback.

## Cluster Note

The current single-node Compose deployment is not a complete multi-node
WebSocket cluster. Before scaling API nodes, implement the Redis event bus,
shared object storage and worker/task coordination described in
`docs/plans/IM完整集群部署与改造方案.md`.
