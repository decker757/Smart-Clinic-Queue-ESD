import { useAuthStore } from '@/stores/auth'

const API_BASE = import.meta.env.VITE_API_BASE_URL ?? ''

function authHeaders(jwt) {
  return { Authorization: `Bearer ${jwt}` }
}

export function useStaff() {
  const authStore = useAuthStore()

  // ─── Queue ─────────────────────────────────────────────────────────────────

  async function fetchQueuePosition(appointmentId) {
    const res = await fetch(
      `${API_BASE}/api/composite/staff/queue/${appointmentId}/position`,
      { headers: authHeaders(authStore.jwt) },
    )
    if (!res.ok) throw new Error('Failed to fetch queue position')
    return res.json()
  }

  async function checkInPatient(appointmentId) {
    const res = await fetch(
      `${API_BASE}/api/composite/staff/queue/${appointmentId}/checkin`,
      {
        method: 'POST',
        headers: authHeaders(authStore.jwt),
      },
    )
    if (!res.ok) {
      const body = await res.json().catch(() => ({}))
      throw new Error(body.detail ?? 'Failed to check in patient')
    }
    return res.json()
  }

  async function markNoShow(appointmentId) {
    const res = await fetch(
      `${API_BASE}/api/composite/staff/queue/${appointmentId}/no-show`,
      {
        method: 'PATCH',
        headers: authHeaders(authStore.jwt),
      },
    )
    if (!res.ok) {
      const body = await res.json().catch(() => ({}))
      throw new Error(body.detail ?? 'Failed to mark no-show')
    }
    return res.json()
  }

  async function removeFromQueue(appointmentId) {
    const res = await fetch(
      `${API_BASE}/api/composite/staff/queue/${appointmentId}`,
      {
        method: 'DELETE',
        headers: authHeaders(authStore.jwt),
      },
    )
    if (!res.ok) {
      const body = await res.json().catch(() => ({}))
      throw new Error(body.detail ?? 'Failed to remove from queue')
    }
    return res.json()
  }

  async function fetchPatient(patientId) {
    const res = await fetch(
      `${API_BASE}/api/composite/staff/patients/${patientId}`,
      { headers: authHeaders(authStore.jwt) },
    )
    if (!res.ok) throw new Error('Failed to fetch patient')
    return res.json()
  }

  async function fetchQueue() {
    const res = await fetch(
      `${API_BASE}/api/queue/active`,
      { headers: authHeaders(authStore.jwt) },
    )
    if (!res.ok) throw new Error('Failed to fetch queue')
    return res.json()
  }

  async function fetchDoctors() {
    const res = await fetch(
      `${API_BASE}/api/composite/staff/doctors`,
      { headers: authHeaders(authStore.jwt) },
    )
    if (!res.ok) throw new Error('Failed to fetch doctors')
    return res.json()
  }

  return {
    fetchQueuePosition,
    checkInPatient,
    markNoShow,
    removeFromQueue,
    fetchPatient,
    fetchQueue,
    fetchDoctors,
  }
}
