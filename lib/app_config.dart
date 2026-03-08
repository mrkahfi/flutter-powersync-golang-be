/// App-level configuration constants.
///
/// Adjust these URLs to match your local setup:
///   - backendUrl  → your Go backend (port 8080)
///   - powerSyncUrl → the PowerSync docker service (port 8081)
library;

/// Your Go backend. Used for auth token requests and data mutations.
const String backendUrl = 'http://localhost:8080';

/// The PowerSync service. The Flutter SDK connects here for sync.
const String powerSyncUrl = 'http://localhost:8081';

/// Fake user ID for local development.
/// Replace with real auth (Supabase, Firebase, etc.) in production.
const String devUserId = 'dev-user-001';
