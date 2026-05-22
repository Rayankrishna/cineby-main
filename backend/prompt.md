Build the backend for "Reelix" — a Flutter movie + TV streaming app.

The frontend is already built. It uses TMDB IDs for content and the Videasy iframe player. The player supports resume via ?progress=<seconds>, so the backend must track per-item progress.

Stack
Node.js + Express (or NestJS), TypeScript
PostgreSQL with Prisma ORM
JWT auth (access + refresh tokens), bcrypt for password hashing
Zod for request validation
Dockerfile + docker-compose.yml for local dev
REST, JSON, /api/v1 prefix
Data model
User — id (uuid), name, email (unique, lowercased), passwordHash, createdAt, updatedAt

WatchHistoryItem — id, userId, tmdbId (int), mediaType ('movie' | 'tv'), seasonNumber (int?, tv only), episodeNumber (int?, tv only), progressSeconds (int), durationSeconds (int?), completed (bool), title, posterPath, backdropPath, watchedAt, updatedAt

Composite unique: (userId, tmdbId, mediaType, seasonNumber, episodeNumber) — upsert when the client reports progress so we don't create duplicate rows per episode.
WatchlistItem — id, userId, tmdbId, mediaType, title, posterPath, addedAt

Composite unique: (userId, tmdbId, mediaType)
Endpoints
Auth (public)

POST /auth/register — body { name, email, password } → returns { user, accessToken, refreshToken }. Validate email format; password min 8 chars; reject duplicate email with 409.
POST /auth/login — body { email, password } → same response shape; 401 on bad credentials.
POST /auth/refresh — body { refreshToken } → new access token.
POST /auth/logout — invalidates the refresh token.
User (auth required)

GET /me — current user profile.
Watch history (auth required)

POST /history — upsert. Body for movie: { tmdbId, mediaType: 'movie', progressSeconds, durationSeconds, title, posterPath, backdropPath }. Body for tv: same fields plus seasonNumber, episodeNumber. Mark completed: true when progressSeconds / durationSeconds >= 0.9.
GET /history — paginated list, newest first. Query: ?limit=20&cursor=<id>&mediaType=movie|tv.
GET /history/continue-watching — items where completed = false and progressSeconds > 30, deduped to one entry per show (latest episode for TV).
GET /history/:tmdbId?mediaType=movie (or ?mediaType=tv&season=&episode=) — for the detail page to know the resume point.
DELETE /history/:id — remove one entry.
DELETE /history — clear all.
Watchlist (auth required)

POST /watchlist — body { tmdbId, mediaType, title, posterPath }. Idempotent: returns 200 if already added.
GET /watchlist — paginated, newest first.
GET /watchlist/contains/:tmdbId?mediaType=movie — returns { inWatchlist: bool } for the heart icon on detail pages.
DELETE /watchlist/:tmdbId?mediaType=movie — remove.
Cross-cutting requirements
Global error middleware → JSON { error: { code, message } }.
Rate-limit /auth/* (e.g. 10/min/IP).
CORS open for dev; restrict by env var for prod.
.env.example with DATABASE_URL, JWT_ACCESS_SECRET, JWT_REFRESH_SECRET, ACCESS_TOKEN_TTL=15m, REFRESH_TOKEN_TTL=30d.
Prisma migrations checked in. Seed script that creates one demo user.
Health check at GET /healthz.
README with: setup, env vars, docker compose up, sample cURL for each endpoint.
Deliverables
Full repo, runnable with docker compose up.
Postman collection or requests.http file with every endpoint.
Unit tests for auth + integration tests for history upsert and watchlist idempotency.
Important: do not store TMDB metadata beyond what's in the schemas above. The frontend already fetches details from TMDB; the backend only persists user-scoped data (history + watchlist).