# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Video conferencing system with WebRTC (Pion SFU) + WebSocket signaling. Vue 3 frontend communicating with a Go/Gin REST + WebSocket backend. MySQL database via GORM with Redis for caching.

```
video-conference-system/
├── video-conference-backend/   # Go/Gin API server
│   ├── handlers/               # Request handlers by domain
│   ├── models/                 # GORM models
│   ├── routers/                # Route registration
│   ├── service/                # Business logic
│   │   ├── ws_serv/            # WebRTC signaling hub + notification hub
│   │   ├── stats_serv/         # Meeting quality report aggregation
│   │   ├── cron_serv/          # Scheduled tasks
│   │   └── common/             # Generic query helpers
│   ├── middleware/             # Auth, binding, rate limiting, permissions
│   ├── flags/                  # CLI flags (-db for migrate, -m user/rbac)
│   ├── core/                   # Logger, config, DB, Redis init
│   └── main.go                 # Entry point
├── video-conference-front/     # Vue 3 SPA
│   └── src/
│       ├── composables/        # useMeetingSession, useWebRTC, useWebRTCStats, useSignaling, useNotificationWS
│       ├── views/              # Page components (auth/, home/, meeting/)
│       ├── component/          # Reusable components (SideBar, MeetingHeader, MeetingFooter, etc.)
│       ├── api/                # Axios API wrappers
│       ├── stores/             # Pinia stores (auth)
│       ├── router/             # Vue Router config
│       └── types/              # TypeScript interfaces
```

## Key Architecture Decisions

- **WebRTC SFU** via Pion — server relays media between peers
- **Signaling** via gorilla/websocket — `service/ws_serv/hub.go` manages rooms and client connections
- **Notifications** — WebSocket-based real-time push via `NotificationHub` in `ws_serv/`, with dependency injection (`NotifPusher` interface) to avoid circular imports between handlers and routers
- **JWT auth** — middleware extracts claims, sets `c.Set("claims", claims)` (NOT `c.Set("userID", ...)`)
- **RBAC** — role-based permission system with cached permission checks
- **Meeting quality stats** — WebRTC getStats() data collected from browser every 7s, sent via WebSocket, stored in `meeting_quality_snapshots` table

## Backend Commands

```bash
# Run server (from video-conference-backend/)
go run main.go                              # uses settings-dev.yaml
go run main.go -f settings.yaml             # custom config
go run main.go -db                          # run DB migrations only
go run main.go -m user -t create            # create a user from CLI
go run main.go -m rbac -t create-role       # manage RBAC from CLI
```

## Frontend Commands

```bash
# Run dev server (from video-conference-front/)
npm run dev

# Build
npm run build

# Type check
npm run type-check

# Lint
npm run lint
```

## Important Patterns

### Adding a new API endpoint
1. Add handler method in `handlers/<domain>/`
2. Add route in `routers/<domain>.go` with required middleware
3. Use `models.BindId` for URI param binding, `middleware.GetAuth(c)` for current user
4. Response helpers: `res.OkWithData`, `res.OkWithList`, `res.FailWithMsg`, `res.FailAuth`

### Adding a new DB model
1. Create model file in `models/`, add to `MigrateModels` in `init()` function
2. Run `go run main.go -db` to migrate

### WebSocket message handling
- Signaling messages flow through `hub.go` — `handleJoinRoom`, `handleOffer`, `handleIceCandidate`, etc.
- Quality reports flow through `handleQualityReport` in `hub.go`
- Notification messages are server-to-client only (client never sends to notification WS)
- New message types: add to the switch in `hub.go`'s message handler

### Frontend composables
- `useMeetingSession(roomNo)` — main orchestrator, wraps signaling + WebRTC + stats
- `useWebRTC()` — manages RTCPeerConnection, tracks/local/remote streams
- `useWebRTCStats()` — collects getStats() every 7s, sends via signaling WS
- `useSignaling()` — WebSocket connection for signaling + quality data
- `useNotificationWS()` — singleton WebSocket for notification push (connect on login, subscribe for updates)
