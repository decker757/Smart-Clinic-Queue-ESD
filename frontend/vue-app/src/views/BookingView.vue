<script setup>
import { ref, computed, onMounted, onUnmounted } from 'vue'
import { useRouter } from 'vue-router'
import { useAuthStore } from '@/stores/auth'

const router = useRouter()
const authStore = useAuthStore()

const API = import.meta.env.VITE_API_BASE_URL ?? ''

const MODE = { SESSION: 'session', DOCTOR: 'doctor' }
const SESSION = { MORNING: 'morning', AFTERNOON: 'afternoon' }

// ── Booking mode ──
const bookingMode = ref(MODE.SESSION)

// ── Shared state ──
const loading = ref(false)
const error = ref('')
const success = ref('')

// ── Mode A: Session ──
const selectedSession = ref(null)

// ── Mode B: Doctor + Date + Slot ──
const doctors = ref([])
const selectedDoctor = ref(null)
const selectedDate = ref('')
const availableSlots = ref([])
const selectedSlot = ref(null)
const slotsLoading = ref(false)
let slotsAbortController = null
let redirectTimer = null

// ── Date constraints (SGT) — recomputed each time they're read ──
function sgtToday() {
  return new Date(Date.now() + 8 * 3_600_000).toISOString().split('T')[0]
}
function sgtMaxDate() {
  return new Date(Date.now() + 8 * 3_600_000 + 30 * 86_400_000).toISOString().split('T')[0]
}

// ── Helpers ──
function authHeaders() {
  return { Authorization: `Bearer ${authStore.jwt}`, 'Content-Type': 'application/json' }
}

function formatSlotTime(slot) {
  const fmt = (d) => new Date(d).toLocaleTimeString('en-SG', { hour: '2-digit', minute: '2-digit' })
  return `${fmt(slot.start_time)} – ${fmt(slot.end_time)}`
}

// ── Computed ──
const canBook = computed(() => {
  if (loading.value) return false
  return bookingMode.value === MODE.SESSION
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
  availableSlots.value = []
  selectedSlot.value = null
  if (selectedDate.value) fetchSlots()
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
    const now = new Date()
    availableSlots.value = (data.slots || data || []).filter(
      (s) => s.status === 'available' && new Date(s.start_time) > now,
    )
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
  if (bookingMode.value === MODE.SESSION) {
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
  const idempotencyKey = crypto.randomUUID()
  try {
    const res = await fetch(`${API}/api/composite/appointments`, {
      method: 'POST',
      headers: { ...authHeaders(), 'X-Idempotency-Key': idempotencyKey },
      body: JSON.stringify(body),
    })
    if (!res.ok) {
      const resp = await res.json().catch(() => ({}))
      throw new Error(resp.detail || 'Booking failed')
    }
    success.value = 'Appointment booked successfully!'
    redirectTimer = setTimeout(() => router.push('/dashboard'), 1500)
  } catch (e) {
    error.value = e.message
  } finally {
    loading.value = false
  }
}

onMounted(fetchDoctors)
onUnmounted(() => {
  slotsAbortController?.abort()
  clearTimeout(redirectTimer)
})
</script>

<template>
  <div class="min-h-dvh bg-surface">

    <!-- ─── Header ──────────────────────────────────────────────────────────── -->
    <header class="sticky top-0 z-20 bg-white border-b border-slate-200">
      <div class="max-w-2xl mx-auto px-4 h-14 flex items-center gap-3">
        <button
          type="button"
          class="flex items-center justify-center w-8 h-8 rounded-lg text-slate-500 hover:text-text hover:bg-slate-100 transition-colors duration-150 cursor-pointer"
          aria-label="Back"
          @click="router.push('/dashboard')"
        >
          <svg class="w-5 h-5" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.75" aria-hidden="true">
            <path stroke-linecap="round" stroke-linejoin="round" d="M15.75 19.5 8.25 12l7.5-7.5" />
          </svg>
        </button>
        <h1 class="font-heading font-semibold text-text text-base">Book an Appointment</h1>
      </div>
    </header>

    <!-- ─── Main ────────────────────────────────────────────────────────────── -->
    <main class="max-w-2xl mx-auto px-4 py-8 space-y-6">

      <!-- Error / Success banners -->
      <div
        v-if="error"
        role="alert"
        class="px-4 py-3 bg-red-50 border border-red-200 rounded-xl text-sm text-red-700"
      >
        {{ error }}
      </div>
      <div
        v-if="success"
        role="status"
        class="px-4 py-3 bg-emerald-50 border border-emerald-200 rounded-xl text-sm text-emerald-700 flex items-center gap-2"
      >
        <svg class="w-4 h-4 shrink-0" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true">
          <path stroke-linecap="round" stroke-linejoin="round" d="M9 12.75 11.25 15 15 9.75M21 12a9 9 0 1 1-18 0 9 9 0 0 1 18 0Z" />
        </svg>
        {{ success }}
      </div>

      <!-- ─── Mode tabs ──────────────────────────────────────────────────────── -->
      <div class="bg-white rounded-2xl border border-slate-200 p-1 flex gap-1">
        <button
          type="button"
          class="flex-1 py-2 px-4 rounded-xl text-sm font-semibold transition-colors duration-150 cursor-pointer"
          :class="bookingMode === MODE.SESSION
            ? 'bg-primary/8 text-primary'
            : 'text-slate-500 hover:text-text'"
          @click="switchMode(MODE.SESSION)"
        >
          Walk-in (Session)
        </button>
        <button
          type="button"
          class="flex-1 py-2 px-4 rounded-xl text-sm font-semibold transition-colors duration-150 cursor-pointer"
          :class="bookingMode === MODE.DOCTOR
            ? 'bg-primary/8 text-primary'
            : 'text-slate-500 hover:text-text'"
          @click="switchMode(MODE.DOCTOR)"
        >
          Book with Doctor
        </button>
      </div>

      <!-- ── Mode A: Walk-in session ── -->
      <div v-if="bookingMode === MODE.SESSION">
        <p class="text-xs font-semibold uppercase tracking-widest text-slate-400 mb-3">Choose a Session</p>
        <div class="grid grid-cols-2 gap-3">
          <button
            type="button"
            class="p-5 text-left bg-white border rounded-2xl transition-colors duration-150 cursor-pointer"
            :class="selectedSession === SESSION.MORNING
              ? 'border-primary bg-primary/8'
              : 'border-slate-200 hover:border-primary/40'"
            @click="selectedSession = SESSION.MORNING"
          >
            <div class="w-9 h-9 rounded-xl flex items-center justify-center mb-3"
              :class="selectedSession === SESSION.MORNING ? 'bg-primary/15' : 'bg-slate-100'">
              <svg class="w-5 h-5" :class="selectedSession === SESSION.MORNING ? 'text-primary' : 'text-slate-400'"
                viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.75" aria-hidden="true">
                <path stroke-linecap="round" stroke-linejoin="round"
                  d="M12 3v2.25m6.364.386-1.591 1.591M21 12h-2.25m-.386 6.364-1.591-1.591M12 18.75V21m-4.773-4.227-1.591 1.591M5.25 12H3m4.227-4.773L5.636 5.636M15.75 12a3.75 3.75 0 1 1-7.5 0 3.75 3.75 0 0 1 7.5 0Z" />
              </svg>
            </div>
            <div class="font-heading font-semibold text-text text-sm">Morning</div>
            <div class="text-xs text-slate-500 mt-0.5">09:00 – 12:00</div>
          </button>

          <button
            type="button"
            class="p-5 text-left bg-white border rounded-2xl transition-colors duration-150 cursor-pointer"
            :class="selectedSession === SESSION.AFTERNOON
              ? 'border-primary bg-primary/8'
              : 'border-slate-200 hover:border-primary/40'"
            @click="selectedSession = SESSION.AFTERNOON"
          >
            <div class="w-9 h-9 rounded-xl flex items-center justify-center mb-3"
              :class="selectedSession === SESSION.AFTERNOON ? 'bg-primary/15' : 'bg-slate-100'">
              <!-- Sunset / half-sun icon for afternoon -->
              <svg class="w-5 h-5" :class="selectedSession === SESSION.AFTERNOON ? 'text-primary' : 'text-slate-400'"
                viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.75" aria-hidden="true">
                <!-- half circle (sun at horizon) -->
                <path stroke-linecap="round" stroke-linejoin="round" d="M4.5 12a7.5 7.5 0 0 1 15 0" />
                <!-- horizon line -->
                <path stroke-linecap="round" stroke-linejoin="round" d="M3 12h18" />
                <!-- rays above -->
                <path stroke-linecap="round" stroke-linejoin="round" d="M12 2.25V4.5" />
                <path stroke-linecap="round" stroke-linejoin="round" d="M18.894 5.106l-1.59 1.59" />
                <path stroke-linecap="round" stroke-linejoin="round" d="M5.106 5.106l1.59 1.59" />
                <!-- glow lines below horizon -->
                <path stroke-linecap="round" stroke-linejoin="round" d="M3 15.75h18" />
                <path stroke-linecap="round" stroke-linejoin="round" d="M4.5 19.5h15" />
              </svg>
            </div>
            <div class="font-heading font-semibold text-text text-sm">Afternoon</div>
            <div class="text-xs text-slate-500 mt-0.5">14:00 – 17:00</div>
          </button>
        </div>
      </div>

      <!-- ── Mode B: Book with doctor ── -->
      <div v-else class="space-y-6">

        <!-- Step 1: Pick doctor -->
        <div>
          <p class="text-xs font-semibold uppercase tracking-widest text-slate-400 mb-3">1. Select a Doctor</p>
          <div v-if="loading && !doctors.length" class="space-y-3">
            <div v-for="i in 3" :key="i" class="bg-white rounded-2xl border border-slate-200 p-4 animate-pulse">
              <div class="h-4 w-32 bg-slate-100 rounded mb-2" />
              <div class="h-3 w-24 bg-slate-100 rounded" />
            </div>
          </div>
          <div class="space-y-2">
            <button
              v-for="doc in doctors"
              :key="doc.id"
              type="button"
              class="w-full p-4 text-left bg-white border rounded-2xl transition-colors duration-150 cursor-pointer flex items-center justify-between"
              :class="selectedDoctor === doc.id
                ? 'border-primary bg-primary/8'
                : 'border-slate-200 hover:border-primary/40'"
              @click="selectDoctor(doc.id)"
            >
              <div>
                <div class="font-heading font-semibold text-text text-sm">{{ doc.name }}</div>
                <div class="text-xs text-slate-500 mt-0.5">{{ doc.specialisation }}</div>
              </div>
              <!-- Selected checkmark -->
              <svg
                v-if="selectedDoctor === doc.id"
                class="w-5 h-5 text-primary shrink-0"
                viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true"
              >
                <path stroke-linecap="round" stroke-linejoin="round" d="M9 12.75 11.25 15 15 9.75M21 12a9 9 0 1 1-18 0 9 9 0 0 1 18 0Z" />
              </svg>
            </button>
          </div>
        </div>

        <!-- Step 2: Pick date -->
        <div v-if="selectedDoctor">
          <p class="text-xs font-semibold uppercase tracking-widest text-slate-400 mb-3">2. Select a Date</p>
          <div class="bg-white rounded-2xl border border-slate-200 p-4">
            <input
              type="date"
              v-model="selectedDate"
              :min="sgtToday()"
              :max="sgtMaxDate()"
              @change="fetchSlots"
              class="w-full text-sm text-text bg-transparent focus:outline-none cursor-pointer"
            />
          </div>
        </div>

        <!-- Step 3: Pick slot -->
        <div v-if="selectedDoctor && selectedDate">
          <p class="text-xs font-semibold uppercase tracking-widest text-slate-400 mb-3">3. Choose a Time Slot</p>
          <div v-if="slotsLoading" class="grid grid-cols-3 gap-2">
            <div v-for="i in 6" :key="i" class="h-11 bg-white border border-slate-200 rounded-xl animate-pulse" />
          </div>
          <p v-else-if="!availableSlots.length" class="text-sm text-slate-500 bg-white rounded-2xl border border-slate-200 px-4 py-3">
            No available slots for this date.
          </p>
          <div v-else class="grid grid-cols-3 gap-2">
            <button
              v-for="slot in availableSlots"
              :key="slot.id"
              type="button"
              class="h-11 text-center text-sm font-medium border rounded-xl transition-colors duration-150 cursor-pointer"
              :class="selectedSlot === slot.id
                ? 'border-primary bg-primary/8 text-primary font-semibold'
                : 'bg-white border-slate-200 text-slate-600 hover:border-primary/40'"
              @click="selectedSlot = slot.id"
            >
              {{ formatSlotTime(slot) }}
            </button>
          </div>
        </div>

      </div>

      <!-- ─── Confirm button ──────────────────────────────────────────────────── -->
      <button
        type="button"
        class="w-full h-11 rounded-xl font-semibold text-sm transition-colors duration-150 focus-visible:outline-3 focus-visible:outline-offset-2 focus-visible:outline-cta"
        :class="canBook
          ? 'bg-cta text-white hover:bg-cta/90 cursor-pointer'
          : 'bg-slate-100 text-slate-400 cursor-not-allowed'"
        :disabled="!canBook"
        @click="bookAppointment"
      >
        {{ loading ? 'Booking…' : 'Confirm Booking' }}
      </button>

    </main>
  </div>
</template>
