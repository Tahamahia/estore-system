# eStore Fulfillment System

A production-ready, multi-tenant e-commerce fulfillment, sorting, and warehouse management system built on Cloudflare's edge infrastructure.

## Architecture

| Layer | Technology | Purpose |
|-------|-----------|---------|
| **API** | Hono on Cloudflare Workers | Edge-deployed REST API |
| **Database** | Cloudflare D1 (SQLite) | Multi-tenant data with RLS |
| **Storage** | Cloudflare R2 | Product images & media |
| **Cache** | Cloudflare KV | Idempotency & session cache |
| **Frontend** | Flutter Web on CF Pages | Dashboard & scanner UI |
| **CI/CD** | GitHub Actions | Auto-deploy on push to `main` |

## Quick Start (Local Development)

```bash
# 1. Backend
cd backend
npm install
npm run db:migrate:local
npm run db:bootstrap:local
npm run dev

# 2. Frontend (separate terminal)
cd frontend
flutter pub get
flutter run -d chrome
```

## Production Deployment

### Prerequisites
1. Cloudflare account with Workers, D1, R2, KV, and Pages enabled
2. GitHub repository connected to Cloudflare

### Step 1: Provision Cloudflare Resources
```bash
cd backend

# Create D1 database
npx wrangler d1 create estore-db
# Copy the database_id into wrangler.toml

# Create KV namespace
npx wrangler kv namespace create CACHE
# Copy the id into wrangler.toml

# Create R2 bucket
npx wrangler r2 bucket create estore-media
```

### Step 2: Set Secrets
```bash
npx wrangler secret put JWT_SECRET
# Enter a strong secret (32+ chars)

# Optional:
npx wrangler secret put SENTRY_DSN
npx wrangler secret put TELEGRAM_BOT_TOKEN
```

### Step 3: Deploy & Initialize
```bash
# Deploy the Worker
npm run deploy

# Apply schema to remote D1
npm run db:migrate

# Bootstrap first tenant + suppliers
npm run db:bootstrap

# Create Super Admin account
curl -X POST https://estore-api.YOUR_SUBDOMAIN.workers.dev/api/v1/auth/register \
  -H "Content-Type: application/json" \
  -d '{
    "id": "admin-super-001",
    "email": "admin@estore.ly",
    "password": "SuperAdmin2026!",
    "full_name": "Super Administrator",
    "tenant_id": "tenant-default",
    "role": "super_admin"
  }'
```

### Step 4: GitHub Secrets (for CI/CD)
Add these in **GitHub → Settings → Secrets and Variables → Actions**:

| Secret | Description |
|--------|-------------|
| `CLOUDFLARE_API_TOKEN` | CF API token with Workers/Pages/D1/R2/KV permissions |
| `CLOUDFLARE_ACCOUNT_ID` | Your Cloudflare account ID |
| `JWT_SECRET` | Same secret used in `wrangler secret put` |
| `SENTRY_DSN` | Sentry DSN (optional, leave empty to disable) |

## API Endpoints

### Public
- `GET /health` — Health check
- `POST /api/v1/auth/register` — Register user
- `POST /api/v1/auth/login` — Login (returns JWT)

### Protected (requires `Authorization: Bearer <token>`)
- `GET/POST/PATCH/DELETE /api/v1/orders`
- `GET/POST /api/v1/customers`
- `GET/POST /api/v1/shipments`
- `POST /api/v1/warehouse/scan`
- `GET /api/v1/analytics/dashboard`
- `POST /api/v1/purchasing/record`
- `POST /api/v1/landed-cost/calculate/:id`
- `GET/POST /api/v1/wallets/:customer_id`
- `GET /api/v1/sync`

## Security
- JWT authentication (HMAC-SHA256 via Web Crypto API)
- Row-Level Security via tenant_id middleware
- PBKDF2 password hashing (100k iterations)
- Optimistic Concurrency Control (version column)
- Idempotency keys via KV cache
- Soft deletes with audit trail

## License
Private — All rights reserved.
