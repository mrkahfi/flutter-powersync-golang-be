// Package handler provides the HTTP handlers for the PowerSync backend API.
//
// Required endpoints:
//
//	GET  /api/auth/token   – Return a signed JWT for the authenticated user.
//	GET  /api/auth/keys    – JWKS endpoint so PowerSync can verify tokens.
//	POST /api/data         – Batch mutations from the client.
//	PUT  /api/data         – Single upsert.
//	PATCH /api/data        – Single update.
//	DELETE /api/data       – Single delete.
package handler

import (
	"context"
	"encoding/json"
	"fmt"
	"log/slog"
	"net/http"
	"time"

	"powersync-backend/auth"
	"powersync-backend/db"
)

// API wires all PowerSync endpoints to the provided ServeMux.
type API struct {
	auth *auth.Manager
	db   *db.Pool
	log  *slog.Logger
}

// New returns a new API with all routes registered on mux.
func New(mux *http.ServeMux, authMgr *auth.Manager, pool *db.Pool, log *slog.Logger) *API {
	a := &API{auth: authMgr, db: pool, log: log}

	mux.HandleFunc("GET /api/auth/token", a.handleToken)
	mux.HandleFunc("GET /api/auth/keys", a.handleKeys)
	mux.HandleFunc("POST /api/data", a.handleDataBatch)
	mux.HandleFunc("PUT /api/data", a.handleDataUpsert)
	mux.HandleFunc("PATCH /api/data", a.handleDataUpdate)
	mux.HandleFunc("DELETE /api/data", a.handleDataDelete)

	// Health probe
	mux.HandleFunc("GET /healthz", func(w http.ResponseWriter, r *http.Request) {
		if err := pool.Ping(r.Context()); err != nil {
			http.Error(w, `{"error":"db unhealthy"}`, http.StatusServiceUnavailable)
			return
		}
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte("ok"))
	})

	return a
}

// ─── Auth endpoints ──────────────────────────────────────────────────────────

// handleToken mints a PowerSync JWT for the caller.
// Pass ?user_id=<id> for now; replace with real session auth in production.
func (a *API) handleToken(w http.ResponseWriter, r *http.Request) {
	userID := r.URL.Query().Get("user_id")
	if userID == "" {
		http.Error(w, `{"error":"user_id query param required"}`, http.StatusBadRequest)
		return
	}

	token, err := a.auth.MintToken(userID)
	if err != nil {
		a.log.Error("mint token", "err", err)
		http.Error(w, `{"error":"internal server error"}`, http.StatusInternalServerError)
		return
	}

	writeJSON(w, http.StatusOK, map[string]interface{}{
		"token":      token,
		"expires_in": 3600,
	})
}

// handleKeys exposes the JWKS so PowerSync can verify tokens.
func (a *API) handleKeys(w http.ResponseWriter, r *http.Request) {
	jwks, err := a.auth.JWKS()
	if err != nil {
		a.log.Error("build JWKS", "err", err)
		http.Error(w, `{"error":"internal server error"}`, http.StatusInternalServerError)
		return
	}
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	_, _ = w.Write(jwks)
}

// ─── Data / mutation endpoints ───────────────────────────────────────────────

// MutationRequest is the body sent by the PowerSync client for writes.
type MutationRequest struct {
	Table string                 `json:"table"`
	Op    string                 `json:"op"` // "PUT" | "PATCH" | "DELETE"
	Data  map[string]interface{} `json:"data"`
	ID    string                 `json:"id"`
}

func (a *API) handleDataBatch(w http.ResponseWriter, r *http.Request) {
	var mutations []MutationRequest
	if err := json.NewDecoder(r.Body).Decode(&mutations); err != nil {
		http.Error(w, `{"error":"invalid JSON"}`, http.StatusBadRequest)
		return
	}

	ctx := r.Context()
	for _, m := range mutations {
		var err error
		switch m.Op {
		case "PUT":
			err = a.upsert(ctx, m.Table, m.Data)
		case "PATCH":
			err = a.update(ctx, m.Table, m.ID, m.Data)
		case "DELETE":
			err = a.delete(ctx, m.Table, m.ID)
		default:
			a.log.Warn("unknown op in batch", "op", m.Op)
		}
		if err != nil {
			a.log.Error("batch mutation failed", "table", m.Table, "op", m.Op, "err", err)
			http.Error(w, fmt.Sprintf(`{"error":%q}`, err.Error()), http.StatusInternalServerError)
			return
		}
	}

	a.log.Info("data batch processed", "count", len(mutations))
	writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
}

func (a *API) handleDataUpsert(w http.ResponseWriter, r *http.Request) {
	var mut MutationRequest
	if err := json.NewDecoder(r.Body).Decode(&mut); err != nil {
		http.Error(w, `{"error":"invalid JSON"}`, http.StatusBadRequest)
		return
	}
	if err := a.upsert(r.Context(), mut.Table, mut.Data); err != nil {
		a.log.Error("upsert", "table", mut.Table, "err", err)
		http.Error(w, fmt.Sprintf(`{"error":%q}`, err.Error()), http.StatusInternalServerError)
		return
	}
	a.log.Info("upsert", "table", mut.Table, "id", mut.ID)
	writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
}

func (a *API) handleDataUpdate(w http.ResponseWriter, r *http.Request) {
	var mut MutationRequest
	if err := json.NewDecoder(r.Body).Decode(&mut); err != nil {
		http.Error(w, `{"error":"invalid JSON"}`, http.StatusBadRequest)
		return
	}
	if err := a.update(r.Context(), mut.Table, mut.ID, mut.Data); err != nil {
		a.log.Error("update", "table", mut.Table, "err", err)
		http.Error(w, fmt.Sprintf(`{"error":%q}`, err.Error()), http.StatusInternalServerError)
		return
	}
	a.log.Info("update", "table", mut.Table, "id", mut.ID)
	writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
}

func (a *API) handleDataDelete(w http.ResponseWriter, r *http.Request) {
	var mut MutationRequest
	if err := json.NewDecoder(r.Body).Decode(&mut); err != nil {
		http.Error(w, `{"error":"invalid JSON"}`, http.StatusBadRequest)
		return
	}
	if err := a.delete(r.Context(), mut.Table, mut.ID); err != nil {
		a.log.Error("delete", "table", mut.Table, "err", err)
		http.Error(w, fmt.Sprintf(`{"error":%q}`, err.Error()), http.StatusInternalServerError)
		return
	}
	a.log.Info("delete", "table", mut.Table, "id", mut.ID)
	writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
}

// ─── DB helpers ──────────────────────────────────────────────────────────────

// allowedTables restricts which tables can be mutated via the API.
// Add your own tables here as needed.
var allowedTables = map[string]bool{
	"todos": true,
	"lists": true,
}

func (a *API) upsert(ctx context.Context, table string, data map[string]interface{}) error {
	if !allowedTables[table] {
		return fmt.Errorf("table %q is not allowed", table)
	}

	id, _ := data["id"].(string)
	if id == "" {
		return fmt.Errorf("upsert: missing id field")
	}

	// Generic upsert into whitelisted tables.
	// For each supported table, build the Postgres-specific upsert.
	// We handle the two example tables explicitly for type safety.
	switch table {
	case "todos":
		_, err := a.db.Exec(ctx, `
			INSERT INTO todos (id, list_id, created_by, description, completed, updated_at)
			VALUES ($1, $2, $3, $4, $5, $6)
			ON CONFLICT (id) DO UPDATE SET
				description = EXCLUDED.description,
				completed   = EXCLUDED.completed,
				updated_at  = EXCLUDED.updated_at`,
			id,
			strVal(data, "list_id"),
			strVal(data, "created_by"),
			strVal(data, "description"),
			boolVal(data, "completed"),
			time.Now(),
		)
		return err
	case "lists":
		_, err := a.db.Exec(ctx, `
			INSERT INTO lists (id, created_by, name, updated_at)
			VALUES ($1, $2, $3, $4)
			ON CONFLICT (id) DO UPDATE SET
				name       = EXCLUDED.name,
				updated_at = EXCLUDED.updated_at`,
			id,
			strVal(data, "created_by"),
			strVal(data, "name"),
			time.Now(),
		)
		return err
	}
	return nil
}

func (a *API) update(ctx context.Context, table, id string, data map[string]interface{}) error {
	if !allowedTables[table] {
		return fmt.Errorf("table %q is not allowed", table)
	}
	if id == "" {
		if v, ok := data["id"].(string); ok {
			id = v
		}
	}
	// Delegate to upsert for simplicity; add partial-update logic per table if needed.
	return a.upsert(ctx, table, data)
}

func (a *API) delete(ctx context.Context, table, id string) error {
	if !allowedTables[table] {
		return fmt.Errorf("table %q is not allowed", table)
	}
	if id == "" {
		return fmt.Errorf("delete: missing id")
	}
	// Postgres doesn't support parameterised table names, so we switch explicitly.
	switch table {
	case "todos":
		_, err := a.db.Exec(ctx, `DELETE FROM todos WHERE id = $1`, id)
		return err
	case "lists":
		_, err := a.db.Exec(ctx, `DELETE FROM lists WHERE id = $1`, id)
		return err
	}
	return nil
}

// ─── Type helpers ─────────────────────────────────────────────────────────────

func strVal(m map[string]interface{}, key string) string {
	if v, ok := m[key]; ok {
		if s, ok := v.(string); ok {
			return s
		}
	}
	return ""
}

func boolVal(m map[string]interface{}, key string) bool {
	if v, ok := m[key]; ok {
		if b, ok := v.(bool); ok {
			return b
		}
	}
	return false
}

// ─── Helpers ──────────────────────────────────────────────────────────────────

func writeJSON(w http.ResponseWriter, status int, v interface{}) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(v)
}
