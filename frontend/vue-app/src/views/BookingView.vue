<script setup>
import { ref, onMounted, computed } from 'vue'
import { useRouter } from 'vue-router'
import { useAuthStore } from '@/stores/auth'

const router = useRouter()
const authStore = useAuthStore()

// ── State ──
const doctors = ref([])
const selectedDoctor = ref(null)
const availableSlots = ref([])
const selectedSlot = ref(null)
const loading = ref(false)
const slotsLoading = ref(false)
const error = ref('')
const success = ref('')
let slotsAbortController = null

const API = import.meta.env.VITE_API_BASE_URL || 'http://localhost:8000'

// ── Helpers ──
function authHeaders() {
  return { Authorization: `Bearer ${authStore.jwt}`, 'Content-Type': 'application/json' }
}

function formatSlotTime(slot) {
  const start = new Date(slot.start_time)
  const end = new Date(slot.end_time)
  const dateStr = start.toLocaleDateString('en-SG', { weekday: 'short', day: 'numeric', month: 'short' })
  const startTime = start.toLocaleTimeString('en-SG', { hour: '2-digit', minute: '2-digit' })
  const endTime = end.toLocaleTimeString('en-SG', { hour: '2-digit', minute: '2-digit' })
  return `${dateStr} — ${startTime} to ${endTime}`
}

const canBook = computed(() => selectedDoctor.value && selectedSlot.value && !loading.value)

// ── API calls ──
async function fetchDoctors() {
  loading.value = true
  error.value = ''
  try {
    const res = await fetch(`${API}/api/composite/staff/doctors`, { headers: authHeaders() })
    if (!res.ok) throw new Error('Failed to load doctors')
    const data = await res.json()
    doctors.value = data.doctors || data || []
  } catch (e) {
    error.value = e.message
  } finally {
    loading.value = false
  }
}

async function fetchSlots(doctorId) {
  // Cancel any in-flight slot request for a previously selected doctor
  slotsAbortController?.abort()
  slotsAbortController = new AbortController()

  selectedDoctor.value = doctorId
  selectedSlot.value = null
  availableSlots.value = []
  slotsLoading.value = true
  error.value = ''
  try {
    const res = await fetch(`${API}/api/composite/staff/doctors/${doctorId}/slots`, {
      headers: authHeaders(),
      signal: slotsAbortController.signal,
    })
    if (!res.ok) throw new Error('Failed to load available slots')
    const data = await res.json()
    availableSlots.value = (data.slots || data || []).filter((s) => s.status === 'available')
  } catch (e) {
    if (e.name !== 'AbortError') error.value = e.message
  } finally {
    slotsLoading.value = false
  }
}

async function bookAppointment() {
  if (!canBook.value) return

  // Validate patient and selected slot before making the request
  const patientId = authStore.user?.id
  if (!patientId) {
    error.value = 'You must be logged in to book an appointment.'
    return
  }

  const slot = availableSlots.value.find((s) => s.id === selectedSlot.value)
  if (!slot) {
    error.value = 'Selected time slot is no longer available. Please choose another slot.'
    return
  }

  loading.value = true
  error.value = ''
  success.value = ''
  try {
    const res = await fetch(`${API}/api/composite/appointments`, {
      method: 'POST',
      headers: authHeaders(),
      body: JSON.stringify({
        patient_id: patientId,
        doctor_id: selectedDoctor.value,
        start_time: slot.start_time,
      }),
    })
    if (!res.ok) {
      const body = await res.json().catch(() => ({}))
      throw new Error(body.detail || 'Booking failed')
    }
    success.value = 'Appointment booked successfully!'
    selectedDoctor.value = null
    selectedSlot.value = null
    availableSlots.value = []
    setTimeout(() => router.push('/dashboard'), 1500)
  } catch (e) {
    error.value = e.message
  } finally {
    loading.value = false
  }
}

onMounted(fetchDoctors)
</script>

<template>
  <div class="min-h-screen bg-gray-50 p-6">
    <div class="max-w-2xl mx-auto">
      <h1 class="text-2xl font-bold text-gray-900 mb-6">Book an Appointment</h1>

      <!-- Error / Success banners -->
      <div v-if="error" class="mb-4 p-4 bg-red-50 border border-red-200 rounded-lg text-red-700">
        {{ error }}
      </div>
      <div
        v-if="success"
        class="mb-4 p-4 bg-green-50 border border-green-200 rounded-lg text-green-700"
      >
        {{ success }}
      </div>

      <!-- Step 1: Pick a doctor -->
      <section class="mb-8">
        <h2 class="text-lg font-semibold text-gray-800 mb-3">1. Select a Doctor</h2>
        <div v-if="loading && !doctors.length" class="text-gray-500">Loading doctors...</div>
        <div class="grid gap-3">
          <button
            v-for="doc in doctors"
            :key="doc.id"
            @click="fetchSlots(doc.id)"
            class="p-4 text-left border rounded-lg transition"
            :class="
              selectedDoctor === doc.id
                ? 'border-blue-500 bg-blue-50'
                : 'border-gray-200 bg-white hover:border-blue-300'
            "
          >
            <div class="font-medium text-gray-900">{{ doc.name }}</div>
            <div class="text-sm text-gray-500">{{ doc.specialisation }}</div>
          </button>
        </div>
      </section>

      <!-- Step 2: Pick a slot -->
      <section v-if="selectedDoctor" class="mb-8">
        <h2 class="text-lg font-semibold text-gray-800 mb-3">2. Choose a Time Slot</h2>
        <div v-if="slotsLoading" class="text-gray-500">Loading available slots...</div>
        <div v-else-if="!availableSlots.length" class="text-gray-500">
          No available slots for this doctor.
        </div>
        <div class="grid gap-2">
          <button
            v-for="slot in availableSlots"
            :key="slot.id"
            @click="selectedSlot = slot.id"
            class="p-3 text-left border rounded-lg text-sm transition"
            :class="
              selectedSlot === slot.id
                ? 'border-blue-500 bg-blue-50'
                : 'border-gray-200 bg-white hover:border-blue-300'
            "
          >
            {{ formatSlotTime(slot) }}
          </button>
        </div>
      </section>

      <!-- Step 3: Confirm -->
      <button
        v-if="selectedDoctor"
        @click="bookAppointment"
        :disabled="!canBook"
        class="w-full py-3 rounded-lg font-medium text-white transition"
        :class="canBook ? 'bg-blue-600 hover:bg-blue-700' : 'bg-gray-300 cursor-not-allowed'"
      >
        {{ loading ? 'Booking...' : 'Confirm Booking' }}
      </button>
    </div>
  </div>
</template>
