<script setup>
import { ref, onMounted, computed } from 'vue'
import { useRouter } from 'vue-router'
import { useAuthStore } from '@/stores/auth'

const router = useRouter()
const authStore = useAuthStore()

const API = import.meta.env.VITE_API_BASE_URL || 'http://localhost:8000'

// ── Booking mode ──
const bookingMode = ref('session') // 'session' | 'doctor'

// ── Shared state ──
const loading = ref(false)
const error = ref('')
const success = ref('')

// ── Mode A: Session ──
const selectedSession = ref(null) // 'morning' | 'afternoon'

// ── Mode B: Doctor + Date + Slot ──
const doctors = ref([])
const selectedDoctor = ref(null)
const selectedDate = ref('')
const availableSlots = ref([])
const selectedSlot = ref(null)
const slotsLoading = ref(false)
let slotsAbortController = null

// ── Date constraints (SGT) ──
const today = new Date(Date.now() + 8 * 3_600_000).toISOString().split('T')[0]
const maxDate = new Date(Date.now() + 8 * 3_600_000 + 30 * 86_400_000).toISOString().split('T')[0]

// ── Helpers ──
function authHeaders() {
  return { Authorization: `Bearer ${authStore.jwt}`, 'Content-Type': 'application/json' }
}

function formatSlotTime(slot) {
  const start = new Date(slot.start_time)
  const end = new Date(slot.end_time)
  const startTime = start.toLocaleTimeString('en-SG', { hour: '2-digit', minute: '2-digit' })
  const endTime = end.toLocaleTimeString('en-SG', { hour: '2-digit', minute: '2-digit' })
  return `${startTime} – ${endTime}`
}

// ── Computed ──
const canBook = computed(() => {
  if (loading.value) return false
  return bookingMode.value === 'session'
    ? !!selectedSession.value
    : !!(selectedDoctor.value && selectedSlot.value)
})

// ── Mode switch ──
function switchMode(mode) {
  bookingMode.value = mode
  error.value = ''
  success.value = ''
  selectedSession.value = null
  selectedDoctor.value = null
  selectedDate.value = ''
  availableSlots.value = []
  selectedSlot.value = null
}

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

function selectDoctor(doctorId) {
  selectedDoctor.value = doctorId
  selectedDate.value = ''
  availableSlots.value = []
  selectedSlot.value = null
}

async function fetchSlots() {
  if (!selectedDoctor.value || !selectedDate.value) return

  slotsAbortController?.abort()
  slotsAbortController = new AbortController()

  selectedSlot.value = null
  availableSlots.value = []
  slotsLoading.value = true
  error.value = ''
  try {
    const res = await fetch(
      `${API}/api/doctors/${selectedDoctor.value}/slots?date=${selectedDate.value}`,
      { headers: authHeaders(), signal: slotsAbortController.signal },
    )
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

  const patientId = authStore.user?.id
  if (!patientId) {
    error.value = 'You must be logged in to book an appointment.'
    return
  }

  let body
  if (bookingMode.value === 'session') {
    body = { patient_id: patientId, session: selectedSession.value }
  } else {
    const slot = availableSlots.value.find((s) => s.id === selectedSlot.value)
    if (!slot) {
      error.value = 'Selected time slot is no longer available. Please choose another slot.'
      return
    }
    body = { patient_id: patientId, doctor_id: selectedDoctor.value, start_time: slot.start_time, slot_id: slot.id }
  }

  loading.value = true
  error.value = ''
  success.value = ''
  try {
    const res = await fetch(`${API}/api/composite/appointments`, {
      method: 'POST',
      headers: authHeaders(),
      body: JSON.stringify(body),
    })
    if (!res.ok) {
      const resp = await res.json().catch(() => ({}))
      throw new Error(resp.detail || 'Booking failed')
    }
    success.value = 'Appointment booked successfully!'
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
      <div v-if="success" class="mb-4 p-4 bg-green-50 border border-green-200 rounded-lg text-green-700">
        {{ success }}
      </div>

      <!-- Mode tabs -->
      <div class="flex gap-1 mb-8 bg-gray-100 p-1 rounded-lg">
        <button
          @click="switchMode('session')"
          class="flex-1 py-2 px-4 rounded-md text-sm font-medium transition"
          :class="bookingMode === 'session' ? 'bg-white shadow text-blue-600' : 'text-gray-600 hover:text-gray-900'"
        >
          Walk-in (Session)
        </button>
        <button
          @click="switchMode('doctor')"
          class="flex-1 py-2 px-4 rounded-md text-sm font-medium transition"
          :class="bookingMode === 'doctor' ? 'bg-white shadow text-blue-600' : 'text-gray-600 hover:text-gray-900'"
        >
          Book with Doctor
        </button>
      </div>

      <!-- ── Mode A: Walk-in session ── -->
      <div v-if="bookingMode === 'session'">
        <section class="mb-8">
          <h2 class="text-lg font-semibold text-gray-800 mb-3">Choose a Session</h2>
          <div class="grid grid-cols-2 gap-3">
            <button
              @click="selectedSession = 'morning'"
              class="p-4 text-left border rounded-lg transition"
              :class="selectedSession === 'morning' ? 'border-blue-500 bg-blue-50' : 'border-gray-200 bg-white hover:border-blue-300'"
            >
              <div class="font-medium text-gray-900">Morning</div>
              <div class="text-sm text-gray-500">09:00 – 12:00</div>
            </button>
            <button
              @click="selectedSession = 'afternoon'"
              class="p-4 text-left border rounded-lg transition"
              :class="selectedSession === 'afternoon' ? 'border-blue-500 bg-blue-50' : 'border-gray-200 bg-white hover:border-blue-300'"
            >
              <div class="font-medium text-gray-900">Afternoon</div>
              <div class="text-sm text-gray-500">14:00 – 17:00</div>
            </button>
          </div>
        </section>
      </div>

      <!-- ── Mode B: Book with doctor ── -->
      <div v-else>
        <!-- Step 1: Pick doctor -->
        <section class="mb-8">
          <h2 class="text-lg font-semibold text-gray-800 mb-3">1. Select a Doctor</h2>
          <div v-if="loading && !doctors.length" class="text-gray-500">Loading doctors...</div>
          <div class="grid gap-3">
            <button
              v-for="doc in doctors"
              :key="doc.id"
              @click="selectDoctor(doc.id)"
              class="p-4 text-left border rounded-lg transition"
              :class="selectedDoctor === doc.id ? 'border-blue-500 bg-blue-50' : 'border-gray-200 bg-white hover:border-blue-300'"
            >
              <div class="font-medium text-gray-900">{{ doc.name }}</div>
              <div class="text-sm text-gray-500">{{ doc.specialisation }}</div>
            </button>
          </div>
        </section>

        <!-- Step 2: Pick date -->
        <section v-if="selectedDoctor" class="mb-8">
          <h2 class="text-lg font-semibold text-gray-800 mb-3">2. Select a Date</h2>
          <input
            type="date"
            v-model="selectedDate"
            :min="today"
            :max="maxDate"
            @change="fetchSlots"
            class="w-full p-3 border border-gray-200 rounded-lg bg-white focus:outline-none focus:border-blue-500"
          />
        </section>

        <!-- Step 3: Pick slot -->
        <section v-if="selectedDoctor && selectedDate" class="mb-8">
          <h2 class="text-lg font-semibold text-gray-800 mb-3">3. Choose a Time Slot</h2>
          <div v-if="slotsLoading" class="text-gray-500">Loading available slots...</div>
          <div v-else-if="!availableSlots.length" class="text-gray-500">No available slots for this date.</div>
          <div class="grid grid-cols-3 gap-2">
            <button
              v-for="slot in availableSlots"
              :key="slot.id"
              @click="selectedSlot = slot.id"
              class="p-3 text-center border rounded-lg text-sm transition"
              :class="selectedSlot === slot.id ? 'border-blue-500 bg-blue-50' : 'border-gray-200 bg-white hover:border-blue-300'"
            >
              {{ formatSlotTime(slot) }}
            </button>
          </div>
        </section>
      </div>

      <!-- Confirm button -->
      <button
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
