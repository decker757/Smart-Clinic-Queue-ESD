// Resolve API and WebSocket base URLs.
// On localhost, always point at the local Docker stack regardless of env vars.
// On any other host (CloudFront, ALB), use the build-time env vars.
const _isLocal = typeof location !== 'undefined' && location.hostname === 'localhost'

export const API_BASE = _isLocal
  ? 'http://localhost:8000'
  : (import.meta.env.VITE_API_BASE_URL ?? '')

export const WS_BASE = _isLocal
  ? 'ws://localhost:3002'
  : (import.meta.env.VITE_WS_BASE_URL ?? import.meta.env.VITE_API_BASE_URL ?? '')
    .replace(/^https/, 'wss').replace(/^http/, 'ws')
