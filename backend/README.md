# Reelix Backend

Node.js + Express + Prisma + PostgreSQL backend for the Reelix Flutter app.
Compatible with Supabase Postgres — just point `DATABASE_URL` at it.

## Quick start (local Postgres via Docker)

```bash
cd backend
cp .env.example .env
docker compose up --build
```

API is then live at `http://localhost:4000`.

## Quick start (no Docker)

```bash
cd backend
cp .env.example .env            # edit DATABASE_URL to your Postgres (or Supabase)
npm install
npx prisma migrate dev --name init
npm run seed                    # optional demo user
npm run dev
```

## Switching to Supabase

1. In your Supabase project → Settings → Database, copy the **Connection string (URI)**.
2. Paste it as `DATABASE_URL` in `.env`. Append `?pgbouncer=true&connection_limit=1` if you use the pooler.
3. Run `npx prisma migrate deploy`.

## Endpoints

All under `/api/v1`. Send `Authorization: Bearer <accessToken>` for protected routes.

### Auth
- `POST /auth/register` — `{ name, email, password }` → `{ user, accessToken, refreshToken }`
- `POST /auth/login` — `{ email, password }` → same shape
- `POST /auth/refresh` — `{ refreshToken }` → `{ accessToken }`
- `POST /auth/logout` — `{ refreshToken }`

### User
- `GET /me`

### History
- `POST /history` — upsert progress
- `GET /history?limit=20&cursor=...&mediaType=movie|tv`
- `GET /history/continue-watching`
- `GET /history/:tmdbId?mediaType=movie` (or `&mediaType=tv&season=1&episode=2`)
- `DELETE /history/:id`
- `DELETE /history`

### Watchlist
- `POST /watchlist` — idempotent
- `GET /watchlist?limit=50&cursor=...`
- `GET /watchlist/contains/:tmdbId?mediaType=movie`
- `DELETE /watchlist/:tmdbId?mediaType=movie`

## Demo cURL

```bash
# register
curl -sX POST localhost:4000/api/v1/auth/register \
  -H 'content-type: application/json' \
  -d '{"name":"Demo","email":"demo@reelix.app","password":"password123"}'

# save progress (movie)
curl -sX POST localhost:4000/api/v1/history \
  -H "authorization: Bearer $TOKEN" -H 'content-type: application/json' \
  -d '{"tmdbId":299534,"mediaType":"movie","progressSeconds":120,"durationSeconds":7000,"title":"Endgame"}'
```
