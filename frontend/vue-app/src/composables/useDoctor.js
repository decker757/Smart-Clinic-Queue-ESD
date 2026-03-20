import { useAuthStore } from '@/stores/auth'

const API_BASE = import.meta.env.VITE_API_BASE_URL ?? ''

function authHeaders(jwt) {
  return { Authorization: `Bearer ${jwt}` }
}

export function useDoctor() {
  const authStore = useAuthStore()

  // ─── Doctor ────────────────────────────────────────────────────────────────

  async function fetchDoctorInfo(doctorId) {
    const res = await fetch(
      `${API_BASE}/api/composite/staff/doctors/${doctorId}`,
      { headers: authHeaders(authStore.jwt) },
    )
    if (!res.ok) throw new Error('Failed to fetch doctor info')
    return res.json()
  }

  async function fetchDoctorSlots(doctorId) {
    const res = await fetch(
      `${API_BASE}/api/composite/staff/doctors/${doctorId}/slots`,
      { headers: authHeaders(authStore.jwt) },
    )
    if (!res.ok) throw new Error('Failed to fetch slots')
    return res.json()
  }

  // ─── Queue ─────────────────────────────────────────────────────────────────

  async function callNextPatient(session, doctorId) {
    const res = await fetch(
      `${API_BASE}/api/composite/staff/queue/call-next`,
      {
        method: 'POST',
        headers: { ...authHeaders(authStore.jwt), 'Content-Type': 'application/json' },
        body: JSON.stringify({ session, doctor_id: doctorId }),
      },
    )
    if (!res.ok) {
      const body = await res.json().catch(() => ({}))
      throw new Error(body.detail ?? 'No patients in queue')
    }
    return res.json()
  }

  async function completeAppointment(appointmentId) {
    const res = await fetch(
      `${API_BASE}/api/composite/staff/queue/${appointmentId}/complete`,
      {
        method: 'PATCH',
        headers: authHeaders(authStore.jwt),
      },
    )
    if (!res.ok) {
      const body = await res.json().catch(() => ({}))
      throw new Error(body.detail ?? 'Failed to complete appointment')
    }
    return res.json()
  }

  // ─── Patient ───────────────────────────────────────────────────────────────

  async function fetchPatient(patientId) {
    const res = await fetch(
      `${API_BASE}/api/composite/staff/patients/${patientId}`,
      { headers: authHeaders(authStore.jwt) },
    )
    if (!res.ok) throw new Error('Failed to fetch patient')
    return res.json()
  }

  async function fetchPatientHistory(patientId) {
    const res = await fetch(
      `${API_BASE}/api/composite/staff/patients/${patientId}/history`,
      { headers: authHeaders(authStore.jwt) },
    )
    if (!res.ok) throw new Error('Failed to fetch patient history')
    return res.json()
  }

  return {
    fetchDoctorInfo,
    fetchDoctorSlots,
    callNextPatient,
    completeAppointment,
    fetchPatient,
    fetchPatientHistory,
  }
}
