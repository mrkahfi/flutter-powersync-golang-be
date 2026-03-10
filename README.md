# flutter_powersync

A Flutter app demonstrating **offline-first, realtime sync** using
[PowerSync](https://www.powersync.com/). Edits made on one device (or directly
via the backend API) are propagated to all connected clients within seconds — no
manual refresh needed.

## Architecture

```
┌─────────────────────┐     JWT auth + sync     ┌──────────────────────┐
│   Flutter App       │ ◄──────────────────────► │  PowerSync Service   │
│  (SQLite on device) │                          │  (Docker, port 8081) │
└─────────────────────┘                          └──────────┬───────────┘
                                                            │ reads WAL
┌─────────────────────┐     REST mutations       ┌──────────▼───────────┐
│   Go Backend        │ ◄──────────────────────► │   PostgreSQL         │
│  (port 8080)        │                          │   (port 5432)        │
└─────────────────────┘                          └──────────────────────┘
                                                 ┌──────────────────────┐
                                                 │  Internal Storage    │
                                                 │  (Managed by Docker) │
                                                 │  (PowerSync engine)  │
                                                 └──────────────────────┘
```

- **Go backend** — handles auth token minting (JWT) and data mutations (REST
  API). Runs natively on the host.
- **PowerSync service** — watches the Postgres WAL for changes and streams them
  to connected Flutter clients. Runs in Docker.
- **Internal Storage** — a MongoDB instance managed by Docker and used
  exclusively by the PowerSync service for sync metadata.
- **PostgreSQL** — the source of truth. Runs natively on the host.
- **Flutter app** — maintains a local SQLite replica, updated in realtime via
  PowerSync.

---

## Prerequisites

| Tool           | Version | Notes                                         |
| -------------- | ------- | --------------------------------------------- |
| Flutter        | ≥ 3.x   | Run `flutter doctor` to verify                |
| Dart SDK       | ≥ 3.8.1 | Comes with Flutter                            |
| Go             | ≥ 1.21  | Only needed to **rebuild** the backend binary |
| PostgreSQL     | ≥ 14    | Must be running natively (not in Docker)      |
| Docker Desktop | Latest  | For PowerSync service infrastructure          |

---

## 1 — PostgreSQL Setup

The PowerSync service connects to Postgres via the host network
(`host.docker.internal`). You must create the database and user before starting
anything else.

```bash
# Connect as your superuser
psql postgres

# Then run:
CREATE USER powersync_user WITH PASSWORD 'powersync_pass';
CREATE DATABASE powersync OWNER powersync_user;
GRANT ALL PRIVILEGES ON DATABASE powersync TO powersync_user;

# Enable logical replication (required by PowerSync)
ALTER SYSTEM SET wal_level = logical;
SELECT pg_reload_conf();
\q
```

> **Important:** After changing `wal_level`, you must **restart PostgreSQL** for
> it to take effect.
>
> On macOS with Homebrew: `brew services restart postgresql@<version>`

Verify the setting took effect:

```bash
psql -U powersync_user -d powersync -c "SHOW wal_level;"
# Should output: logical
```

The Go backend auto-creates the `todos` and `lists` tables on first run — no
manual migration needed.

---

## 2 — Docker Setup (PowerSync)

```bash
# From the project root
cd server
docker compose up -d
```

Verify containers are running:

```bash
docker ps
# You should see the PowerSync and storage containers running
```

> **Note:** The `version` field warning in docker-compose.yml output is harmless
> and can be ignored.

---

## 3 — Go Backend Setup

The compiled binary is already included in `server/powersync-backend`. Run it
directly:

```bash
cd server

DEV_MODE=true \
POWERSYNC_URL=http://localhost:8081 \
DATABASE_URI=postgres://powersync_user:powersync_pass@localhost:5432/powersync?sslmode=disable \
PORT=8080 \
./powersync-backend
```

You should see:

```
level=INFO  msg="no .env file found, using environment variables"
level=WARN  msg="running in DEV MODE — do not use in production!"
level=INFO  msg="db: schema up-to-date"
level=INFO  msg="postgres connected"
level=INFO  msg="PowerSync backend listening" addr=:8080
```

> **Tip:** Use a `.env` file (see `.env.example`) and `make run` to avoid typing
> env vars every time. In `DEV_MODE=true`, a throwaway RSA key is generated on
> each start — this is fine for local development.

### Optional: Rebuild the binary

If you make changes to the Go source:

```bash
cd server
go build -o powersync-backend .
```

---

## 4 — Flutter App Setup

```bash
# From the project root
flutter pub get
```

### iOS extra step

```bash
cd ios
pod install
cd ..
```

### Configure backend URLs

Edit `lib/app_config.dart` if your backend runs on a different host/port:

```dart
const String backendUrl   = 'http://localhost:8080'; // Go backend
const String powerSyncUrl = 'http://localhost:8081'; // PowerSync service
const String devUserId    = 'dev-user-001';          // Fake user for local dev
```

> **Android emulator note:** Android emulators cannot reach `localhost` on the
> host machine. Use `http://10.0.2.2:8080` and `http://10.0.2.2:8081` instead.

### Run the app

```bash
flutter run
```

---

## Verifying Realtime Sync

With the app running and connected, insert data directly via the backend API and
watch it appear on the device within **1–2 seconds**.

### Insert a list

```bash
curl -s -X PUT http://localhost:8080/api/data \
  -H 'Content-Type: application/json' \
  -d '{
    "table": "lists",
    "op": "PUT",
    "id": "list-001",
    "data": {
      "id": "list-001",
      "created_by": "dev-user-001",
      "name": "My First List"
    }
  }'
```

### Insert a todo

```bash
curl -s -X PUT http://localhost:8080/api/data \
  -H 'Content-Type: application/json' \
  -d '{
    "table": "todos",
    "op": "PUT",
    "id": "todo-001",
    "data": {
      "id": "todo-001",
      "list_id": "list-001",
      "created_by": "dev-user-001",
      "description": "Test realtime sync!",
      "completed": false
    }
  }'
```

> **To add more rows:** Change the `id` field to a new unique value. Reusing an
> existing `id` will **update** that row (upsert behavior).

### Update a row

```bash
curl -s -X PATCH http://localhost:8080/api/data \
  -H 'Content-Type: application/json' \
  -d '{
    "table": "todos",
    "op": "PATCH",
    "id": "todo-001",
    "data": {
      "id": "todo-001",
      "list_id": "list-001",
      "created_by": "dev-user-001",
      "description": "Updated description",
      "completed": true
    }
  }'
```

### Delete a row

```bash
curl -s -X DELETE http://localhost:8080/api/data \
  -H 'Content-Type: application/json' \
  -d '{"table": "todos", "op": "DELETE", "id": "todo-001"}'
```

### Health check

```bash
curl http://localhost:8080/healthz          # Go backend
curl http://localhost:8081                  # PowerSync service (404 is normal)
curl 'http://localhost:8080/api/auth/token?user_id=dev-user-001'  # Auth token
```

---

## Startup Order

Always start components in this order:

1. **PostgreSQL** (must already be running)
2. **Docker Desktop** → then `docker compose up -d` (PowerSync infrastructure)
3. **Go backend** → `./powersync-backend` with env vars
4. **Flutter app** → `flutter run`

---

## Project Structure

```
flutter_powersync/
├── lib/
│   ├── app_config.dart          # Backend URLs and dev user ID
│   ├── main.dart                # App entry point and UI
│   ├── database/
│   │   ├── powersync.dart       # PowerSync DB initialization & connection
│   │   ├── schema.dart          # SQLite schema (must match Postgres)
│   │   └── connector.dart       # Auth token fetching & mutation upload
│   └── models/                  # Data models
├── server/
│   ├── main.go                  # Go server entry point
│   ├── handler/handler.go       # REST API handlers
│   ├── auth/auth.go             # JWT minting & JWKS
│   ├── db/db.go                 # Postgres connection & migrations
│   ├── config/config.go         # Environment variable loading
│   ├── powersync.yaml           # PowerSync service config
│   ├── sync_rules.yaml          # Which tables get synced to clients
│   ├── docker-compose.yml       # PowerSync service infrastructure
│   ├── .env.example             # Template for environment variables
│   ├── Makefile                 # Shortcuts: make run, make build, make keys
│   └── powersync-backend        # Pre-built binary
└── pubspec.yaml
```

---

## Sync Rules

`server/sync_rules.yaml` controls what data gets synced to clients. Currently
all rows from both tables are sent to all users (global bucket):

```yaml
bucket_definitions:
  global:
    data:
      - SELECT * FROM todos
      - SELECT * FROM lists
```

To scope data per user (e.g. only sync a user's own todos), update this file and
restart the PowerSync Docker container:

```yaml
bucket_definitions:
  by_user:
    parameters: SELECT token_parameters.user_id
    data:
      - SELECT * FROM todos WHERE created_by = bucket.user_id
      - SELECT * FROM lists WHERE created_by = bucket.user_id
```

---

## Troubleshooting

| Symptom                        | Likely cause                         | Fix                                                               |
| ------------------------------ | ------------------------------------ | ----------------------------------------------------------------- |
| App shows "Offline" badge      | Backend not running                  | Start the Go backend (step 3)                                     |
| `curl` exit code 7             | Go backend not running               | Start the Go backend (step 3)                                     |
| `curl` zsh glob error          | Unquoted URL with `?`                | Wrap URL in single quotes: `'http://...'`                         |
| PowerSync can't reach Postgres | `wal_level` not `logical`            | Set `wal_level = logical` and restart Postgres                    |
| iOS `pod install` fails        | Missing modular headers              | See `ios/Podfile` — ensure `:modular_headers => true` for sqlite3 |
| Android can't reach backend    | `localhost` doesn't work in emulator | Use `10.0.2.2` instead of `localhost`                             |
| Docker daemon not running      | Docker Desktop closed                | Open Docker Desktop, wait ~30s, then `docker compose up -d`       |
