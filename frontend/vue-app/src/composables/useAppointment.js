import { useAuthStore } from '@/stores/auth'

const API_BASE = import.meta.env.VITE_API_BASE_URL ?? ''

// Active appointment statuses — completed/cancelled/no_show are ignored.
const ACTIVE_STATUSES = new Set(['scheduled', 'checked_in', 'in_progress'])

// Appointment-service status → dashboard UI status
const APPT_STATUS_MAP = {
  scheduled:   'waiting',
  checked_in:  'checked_in',
  in_progress: 'called',
}

// Queue-coordinator status → dashboard UI status (same semantics, different source)
const QUEUE_STATUS_MAP = {
  waiting:    'waiting',
  checked_in: 'checked_in',
  called:     'called',
}

function authHeaders(jwt) {
  return { Authorization: `Bearer ${jwt}` }
}

export function calculateEtaMinutes(estimatedTime) {
  if (!estimatedTime) return null
  const diff = new Date(estimatedTime) - Date.now()
  return diff > 0 ? Math.round(diff / 60000) : 0
}

function formatAppointmentTime(appt) {
  if (appt.start_time) {
    const d = new Date(appt.start_time)
    return d.toLocaleTimeString('en-SG', { hour: '2-digit', minute: '2-digit' })
  }
  return appt.session === 'afternoon' ? 'Afternoon session' : 'Morning session'
}

function formatAppointmentDate(appt) {
  if (appt.start_time) {
    return new Date(appt.start_time).toLocaleDateString('en-SG', {
      weekday: 'short', day: 'numeric', month: 'short', year: 'numeric',
    })
  }
  return new Date().toLocaleDateString('en-SG', {
    weekday: 'short', day: 'numeric', month: 'short', year: 'numeric',
  })
}

// Derive the WS base URL from the HTTP API base
// e.g. https://kong.railway.app → wss://kong.railway.app
//      http://localhost:8000    → ws://localhost:8000
//      '' (same origin)         → ws://<current host>
export function wsBase() {
  if (!API_BASE) {
    const proto = location.protocol === 'https:' ? 'wss' : 'ws'
    return `${proto}://${location.host}`
  }
  return API_BASE.replace(/^https/, 'wss').replace(/^http/, 'ws')
}

/**
 * Merge a raw queue-coordinator entry into an existing dashboard appointment object.
 * Keeps all other fields intact; only overwrites queue-derived fields.
 */
export function mapQueueEntry(currentAppt, entry) {
  return {
    ...currentAppt,
    queueNumber: entry.queue_number ?? currentAppt.queueNumber,
    etaMinutes:  calculateEtaMinutes(entry.estimated_time) ?? currentAppt.etaMinutes,
    status:      QUEUE_STATUS_MAP[entry.status] ?? currentAppt.status,
  }
}

export function useAppointment() {
  const authStore = useAuthStore()

  /**
   * Fetches the patient's next active appointment and its live queue position.
   * Returns null if no active appointment exists.
   *
   * @returns {Promise<object|null>}
   */
  async function fetchDashboardData() {
    const jwt = authStore.jwt
    const patientId = authStore.user?.id
    if (!jwt || !patientId) throw new Error('Not authenticated')

    // 1. List all appointments for this patient
    const apptRes = await fetch(
      `${API_BASE}/api/composite/appointments?patient_id=${patientId}`,
      { headers: authHeaders(jwt) },
    )
    if (!apptRes.ok) throw new Error('Failed to fetch appointments')

    const appts = await apptRes.json()

    // Pick the earliest active appointment
    const appt = (appts ?? [])
      .filter((a) => ACTIVE_STATUSES.has(a.status))
      .sort((a, b) => new Date(a.start_time ?? a.created_at) - new Date(b.start_time ?? b.created_at))[0] ?? null

    if (!appt) return null

    // 2. Get live queue position (may be absent if queue-coordinator hasn't
    //    processed the booking event yet)
    let queueEntry = null
    const queueRes = await fetch(
      `${API_BASE}/api/queue/position/${appt.id}`,
      { headers: authHeaders(jwt) },
    )
    if (queueRes.ok) {
      queueEntry = await queueRes.json()
      // Queue entry is terminal — appointment is over, treat as no active appointment
      if (queueEntry.status === 'done' || queueEntry.status === 'cancelled') return null
    } else if (queueRes.status !== 404) {
      // 404 means not in queue yet — anything else is a real error
      throw new Error('Failed to fetch queue position')
    }

    return {
      id:          appt.id,
      doctor:      appt.doctor_id ? 'Assigned Doctor' : 'Any Available Doctor',
      specialty:   appt.session
        ? `${appt.session.charAt(0).toUpperCase() + appt.session.slice(1)} Session`
        : 'General Practice',
      date:        formatAppointmentDate(appt),
      time:        formatAppointmentTime(appt),
      // Location is a clinic-level config; placeholder until a clinic-info endpoint exists
      location:    'Sunshine Polyclinic · Block A Level 2',
      queueNumber: queueEntry?.queue_number ?? null,
      etaMinutes:  calculateEtaMinutes(queueEntry?.estimated_time),
      // Prefer live queue status (more current) over appointment-service status
      status: (queueEntry && QUEUE_STATUS_MAP[queueEntry.status])
        ?? APPT_STATUS_MAP[appt.status]
        ?? 'waiting',
    }
  }

  /**
   * Opens a WebSocket connection for live queue updates on a specific appointment,
   * with automatic exponential-backoff reconnection.
   *
   * JWT is passed as `?token=` because browsers cannot set custom headers during
   * the HTTP→WS upgrade handshake. Kong validates the signature; the service
   * decodes the payload to verify appointment ownership.
   *
   * @param {string} appointmentId
   * @param {function} onUpdate  Called with a parsed queue entry object on each push
   * @returns {{ close: function }}  Call close() in onUnmounted to clean up
   */
  function connectQueueWebSocket(appointmentId, onUpdate) {
    let ws = null
    let reconnectTimer = null
    let attempt = 0
    let deliberatelyClosed = false
    const MAX_DELAY_MS = 30_000

    function connect() {
      // Re-read jwt on each attempt so a token refresh is picked up automatically
      const jwt = authStore.jwt
      if (!jwt) return // signed out — stop retrying

      const url = `${wsBase()}/api/queue/ws?appointment_id=${appointmentId}&token=${jwt}`
      ws = new WebSocket(url)

      ws.addEventListener('open', () => {
        attempt = 0 // reset backoff counter on successful connection
      })

      ws.addEventListener('message', (event) => {
        try {
          onUpdate(JSON.parse(event.data))
        } catch {
          // malformed frame — ignore
        }
      })

      ws.addEventListener('close', ({ code }) => {
        if (deliberatelyClosed) return
        // 1008 = policy violation (bad auth / missing params) — retrying won't help
        if (code === 1008) {
          console.warn('[WS] Closed by server (auth error) — not retrying')
          return
        }
        const delay = Math.min(1_000 * 2 ** attempt, MAX_DELAY_MS)
        attempt++
        console.warn(`[WS] Disconnected — reconnecting in ${delay}ms (attempt ${attempt})`)
        reconnectTimer = setTimeout(connect, delay)
      })
    }

    connect()

    return {
      close() {
        deliberatelyClosed = true
        clearTimeout(reconnectTimer)
        ws?.close()
      },
    }
  }

  /**
   * Checks the patient in for a given appointment.
   * @param {string} appointmentId
   */
  async function checkIn(appointmentId) {
    const res = await fetch(
      `${API_BASE}/api/queue/checkin/${appointmentId}`,
      { method: 'POST', headers: authHeaders(authStore.jwt) },
    )
    if (!res.ok) {
      const body = await res.json().catch(() => ({}))
      throw new Error(body.error ?? 'Check-in failed. Please try again.')
    }
    return res.json()
  }

  return { fetchDashboardData, connectQueueWebSocket, checkIn }
}
