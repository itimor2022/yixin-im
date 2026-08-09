# GenericIM Architecture

## Runtime Components

```text
Flutter / H5 clients
          |
      HTTPS + WebSocket
          |
       Go API
      /   |    \
 MySQL MongoDB Redis
          |
      S3 / OSS media
```

- MySQL stores accounts, relationships, settings, wallet and operational
  records.
- MongoDB stores message and media-related document data where configured.
- Redis stores cache, rate limits, session coordination, queues and temporary
  online state.
- Object storage stores uploaded images, videos, audio and files.
- The WebSocket Hub manages connections within one API process. Full
  multi-node WebSocket delivery requires the Redis event-bus work described in
  `docs/plans/IM完整集群部署与改造方案.md`.

## Request Boundaries

- API handlers validate authentication, ownership and business permissions.
- Persistent writes are authoritative; WebSocket events are delivery hints.
- Clients recover message gaps through sequence-based HTTP synchronization.
- Media processing uses FFmpeg/ffprobe in the backend image when S3 processing
  is enabled.

## Deployment Modes

### Single Node

Use `compose.yaml` for local development and small installations. Local
uploads are acceptable only when the API and storage share the same host.

### Multi-Node

Use an external load balancer, multiple stateless API nodes, shared Redis,
shared databases and S3/OSS. Do not use per-node local uploads as shared
storage. See the complete cluster plan linked above before enabling multiple
WebSocket-serving API nodes.

## Trust Boundaries

- Public clients are untrusted.
- API validates all authorization and media metadata.
- Admin frontends require separate privileged credentials.
- Database, Redis and object storage endpoints remain private.
- Secrets are injected at deployment time and are never part of the source
  package.
