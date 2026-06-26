# eStore Fulfillment System

A production-ready, multi-tenant e-commerce fulfillment, sorting, and warehouse management system.

## Architecture

```
├── backend/          # Cloudflare Workers (Hono API)
├── frontend/         # Flutter Web App
└── .github/workflows # CI/CD Pipelines
```

## Tech Stack

- **Frontend**: Flutter Web (Riverpod, Freezed, go_router)
- **Backend**: Cloudflare Workers + Hono (MVC)
- **Database**: Cloudflare D1 (SQLite)
- **Storage**: Cloudflare R2 (media), KV (caching/idempotency)
- **Real-time**: Cloudflare Durable Objects (WebSockets)

## Development

### Backend
```bash
cd backend
npm install
npm run dev
```

### Frontend
```bash
cd frontend
flutter pub get
flutter run -d chrome
```
