<script setup>
import { ref, computed, onMounted, onUnmounted } from 'vue'
import { useAuthStore } from '@/stores/auth'
import { useAuth } from '@/composables/useAuth'
import { useStaff } from '@/composables/useStaff'
import { wsBase } from '@/composables/useAppointment'
import { formatGender, formatDOB } from '@/utils/formatters'
import AppAlert from '@/components/ui/AppAlert.vue'

const TERMINAL = new Set(['done', 'cancelled'])

const authStore = useAuthStore()
const { signOut } = useAuth()
const {
  checkInPatient,
  markNoShow,
  deprioritizePatient,
  removeFromQueue,
  fetchPatient,
  fetchDoctors,
  fetchPendingBilling,
  fetchPrescription,
  createBilling,
} = useStaff()

// ─── State ───────────────────────────────────────────────────────────────────
const loading = ref(true)
const error = ref('')
const actionError = ref('')
const actionSuccess = ref('')

const doctors = ref([])
const queue = ref([])
const selectedPatient = ref(null)
const showPatientModal = ref(false)
const patientLoading = ref(false)
const actionLoadingId = ref(null) // tracks which row is loading

// ─── Billing State ──────────────────────────────────────────────────────────
const BASE_CONSULT_CENTS = 2000 // $20.00 SGD base consultation fee
const pendingBilling = ref([])
const billingLoading = ref(false)
const expandedBillingId = ref(null)
const prescriptionMap = ref({})    // appointmentId → [memos]
const billingAmounts = ref({})     // appointmentId → amount in cents
const billingSubmitting = ref(null)
const billingSuccess = ref('')

let queueWs = null
let reconnectTimer = null
let reconnectAttempt = 0
const MAX_RECONNECT_DELAY = 30_000

// ─── Computed ─────────────────────────────────────────────────────────────────
const greeting = computed(() => {
  const h = new Date().getHours()
  if (h < 12) return 'Good morning'
  if (h < 18) return 'Good afternoon'
  return 'Good evening'
})

const firstName = computed(() => authStore.user?.name?.split(' ')[0] ?? 'there')

const queueStats = computed(() => ({
  total:     queue.value.length,
  waiting:   queue.value.filter((q) => q.status === 'waiting').length,
  checkedIn: queue.value.filter((q) => q.status === 'checked_in').length,
  called:    queue.value.filter((q) => q.status === 'called').length,
}))

const STATUS_BADGE = {
  waiting:    { label: 'Waiting',    classes: 'bg-amber-100 text-amber-700',   accent: 'bg-amber-400' },
  checked_in: { label: 'Checked In', classes: 'bg-emerald-100 text-emerald-700', accent: 'bg-emerald-400' },
  called:     { label: 'Called',     classes: 'bg-primary/10 text-primary',    accent: 'bg-primary' },
  no_show:    { label: 'No Show',    classes: 'bg-red-100 text-red-600',       accent: 'bg-red-400' },
  completed:  { label: 'Completed',  classes: 'bg-slate-100 text-slate-500',   accent: 'bg-slate-300' },
}

function statusBadge(status) {
  return STATUS_BADGE[status] ?? { label: status, classes: 'bg-slate-100 text-slate-500', accent: 'bg-slate-300' }
}

function queueSortValue(entry) {
  return entry?.sort_key ?? (entry?.queue_number ?? 0) * 1000
}

function compareQueueEntries(a, b) {
  return queueSortValue(a) - queueSortValue(b) || (a.queue_number ?? 0) - (b.queue_number ?? 0)
}

function etaMinutes(entry) {
  // Use server-computed estimated_time if available; otherwise derive from local queue state
  if (entry.estimated_time) {
    const diff = new Date(entry.estimated_time) - Date.now()
    return diff > 0 ? Math.round(diff / 60000) : 0
  }
  const activeAhead = queue.value.filter(
    (e) => (
      !TERMINAL.has(e.status)
      && queueSortValue(e) < queueSortValue(entry)
      && (
        (entry.doctor_id && e.doctor_id === entry.doctor_id)
        || (!entry.doctor_id && e.session === entry.session && !e.doctor_id)
      )
    ),
  ).length
  return activeAhead * 15
}

// ─── Data loading ─────────────────────────────────────────────────────────────
async function loadDoctors() {
  try {
    doctors.value = (await fetchDoctors()) ?? []
  } catch {
    error.value = 'Could not load doctors. Please refresh.'
  }
}

function connectQueueSocket() {
  if (queue.value.length === 0) loading.value = true
  const url = `${wsBase()}/api/queue/ws/staff?token=${authStore.jwt}`
  const ws = new WebSocket(url)

  ws.addEventListener('open', () => {
    reconnectAttempt = 0
    error.value = ''
  })

  ws.addEventListener('message', (event) => {
    try {
      const msg = JSON.parse(event.data)
      if (msg.type === 'snapshot') {
        queue.value = [...(msg.entries ?? [])].sort(compareQueueEntries)
        loading.value = false
      } else if (msg.type === 'update') {
        const entry = msg.entry
        if (TERMINAL.has(entry.status)) {
          queue.value = queue.value.filter((q) => q.appointment_id !== entry.appointment_id)
        } else {
          const idx = queue.value.findIndex((q) => q.appointment_id === entry.appointment_id)
          const nextQueue = [...queue.value]
          if (idx !== -1) nextQueue[idx] = entry
          else nextQueue.push(entry)
          queue.value = nextQueue.sort(compareQueueEntries)
        }
      }
    } catch {
      // malformed frame — ignore
    }
  })

  ws.addEventListener('close', ({ code }) => {
    loading.value = false
    if (code === 1008) return // bad auth — don't retry
    error.value = 'Lost connection to queue. Reconnecting...'
    const delay = Math.min(1_000 * 2 ** reconnectAttempt, MAX_RECONNECT_DELAY)
    reconnectAttempt++
    reconnectTimer = setTimeout(connectQueueSocket, delay)
  })

  ws.addEventListener('error', () => {
    loading.value = false
  })

  queueWs = ws
}

// ─── Actions ──────────────────────────────────────────────────────────────────
async function handleQueueAction(appointmentId, action, successMsg, newStatus) {
  actionError.value = ''
  actionSuccess.value = ''
  actionLoadingId.value = appointmentId
  try {
    await action(appointmentId)
    actionSuccess.value = successMsg
    setTimeout(() => { actionSuccess.value = '' }, 3000)
    if (newStatus) {
      const entry = queue.value.find((q) => q.appointment_id === appointmentId)
      if (entry) entry.status = newStatus
    } else {
      queue.value = queue.value.filter((q) => q.appointment_id !== appointmentId)
    }
  } catch (e) {
    actionError.value = e.message ?? 'Action failed'
  } finally {
    actionLoadingId.value = null
  }
}

const handleCheckIn     = (id) => handleQueueAction(id, checkInPatient,     'Patient checked in successfully!', 'checked_in')
const handleNoShow      = (id) => handleQueueAction(id, markNoShow,          'Patient marked as no-show.',       'no_show')
const handleDeprioritize = (id) => handleQueueAction(id, deprioritizePatient, 'Patient moved to back of queue.',  'waiting')
const handleRemove      = (id) => handleQueueAction(id, removeFromQueue,     'Patient removed from queue.',      null)

async function handleViewPatient(patientId) {
  if (!patientId) return
  showPatientModal.value = true
  patientLoading.value = true
  selectedPatient.value = null
  try {
    selectedPatient.value = await fetchPatient(patientId)
  } catch {
    actionError.value = 'Failed to load patient details'
    showPatientModal.value = false
  } finally {
    patientLoading.value = false
  }
}

// ─── Billing Actions ─────────────────────────────────────────────────────────
async function loadPendingBilling() {
  billingLoading.value = true
  try {
    const items = await fetchPendingBilling()
    pendingBilling.value = items ?? []
    // Initialise default amounts for new items
    for (const appt of pendingBilling.value) {
      if (!(appt.id in billingAmounts.value)) {
        billingAmounts.value[appt.id] = BASE_CONSULT_CENTS
      }
    }
  } catch (e) {
    actionError.value = e.message ?? 'Failed to load pending billing'
  } finally {
    billingLoading.value = false
  }
}

async function toggleBillingExpand(appointmentId) {
  if (expandedBillingId.value === appointmentId) {
    expandedBillingId.value = null
    return
  }
  expandedBillingId.value = appointmentId
  // Load prescription if not cached
  if (!prescriptionMap.value[appointmentId]) {
    try {
      const memos = await fetchPrescription(appointmentId)
      prescriptionMap.value[appointmentId] = memos ?? []
    } catch (e) {
      actionError.value = e.message ?? 'Failed to load billing details'
      prescriptionMap.value[appointmentId] = []
    }
  }
}

function formatDollars(cents) {
  return `$${(cents / 100).toFixed(2)}`
}

async function handleSubmitBilling(appt) {
  billingSubmitting.value = appt.id
  billingSuccess.value = ''
  actionError.value = ''
  try {
    await createBilling({
      appointmentId: appt.id,
      amountCents: billingAmounts.value[appt.id] ?? BASE_CONSULT_CENTS,
      currency: 'sgd',
    })
    billingSuccess.value = `Billing created for appointment ${appt.id.slice(0, 8).toUpperCase()}. Patient can now pay from their appointment history.`
    setTimeout(() => { billingSuccess.value = '' }, 4000)
    // Remove from pending list
    pendingBilling.value = pendingBilling.value.filter((a) => a.id !== appt.id)
  } catch (e) {
    actionError.value = e.message ?? 'Failed to submit billing'
  } finally {
    billingSubmitting.value = null
  }
}

onMounted(() => {
  loadDoctors()
  connectQueueSocket()
  loadPendingBilling()
})

onUnmounted(() => {
  clearTimeout(reconnectTimer)
  queueWs?.close()
})
</script>

<template>
  <div class="min-h-dvh bg-surface">

    <!-- ─── Header ───────────────────────────────────────────────────────── -->
    <header class="sticky top-0 z-20 bg-white border-b border-slate-200">
      <div class="max-w-4xl mx-auto px-4 h-14 flex items-center justify-between">
        <div class="flex items-center gap-2">
          <svg class="w-6 h-6 text-primary" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true">
            <path fill-rule="evenodd"
              d="M12 2.25a.75.75 0 0 1 .75.75v8.25H21a.75.75 0 0 1 0 1.5h-8.25V21a.75.75 0 0 1-1.5 0v-8.25H3a.75.75 0 0 1 0-1.5h8.25V3a.75.75 0 0 1 .75-.75Z"
              clip-rule="evenodd" />
          </svg>
          <span class="font-heading font-semibold text-text text-sm tracking-tight">SmartClinic</span>
          <span class="text-xs font-medium px-2 py-0.5 rounded-full bg-primary/10 text-primary ml-1">
            Staff
          </span>
        </div>
        <div class="flex items-center gap-3">
          <span class="text-sm text-slate-500 hidden sm:inline">{{ authStore.user?.name }}</span>
          <button
            type="button"
            class="flex items-center gap-1.5 text-sm text-slate-500 hover:text-text transition-colors duration-150 cursor-pointer"
            aria-label="Sign out"
            @click="signOut"
          >
            <svg class="w-5 h-5" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.75" aria-hidden="true">
              <path stroke-linecap="round" stroke-linejoin="round"
                d="M15.75 9V5.25A2.25 2.25 0 0 0 13.5 3h-6a2.25 2.25 0 0 0-2.25 2.25v13.5A2.25 2.25 0 0 0 7.5 21h6a2.25 2.25 0 0 0 2.25-2.25V15M18 15l3-3m0 0-3-3m3 3H9" />
            </svg>
            <span class="sr-only sm:not-sr-only">Sign out</span>
          </button>
        </div>
      </div>
    </header>

    <!-- ─── Main ─────────────────────────────────────────────────────────── -->
    <main class="max-w-4xl mx-auto px-4 py-8 space-y-8">

      <!-- Greeting -->
      <div>
        <p class="text-sm text-slate-500 font-body">{{ greeting }},</p>
        <h1 class="font-heading font-semibold text-2xl text-text">{{ firstName }}</h1>
      </div>

      <!-- Feedback banners -->
      <AppAlert v-if="error" :message="error" />
      <AppAlert v-if="actionError" :message="actionError" />
      <div
        v-if="actionSuccess"
        role="status"
        class="px-4 py-3 bg-emerald-50 border border-emerald-200 rounded-lg text-sm text-emerald-700"
      >
        {{ actionSuccess }}
      </div>

      <!-- ─── Queue Stats ─────────────────────────────────────────────── -->
      <section aria-labelledby="stats-heading">
        <h2 id="stats-heading" class="text-xs font-semibold uppercase tracking-widest text-slate-400 mb-3">
          Live Queue Overview
        </h2>

        <div class="grid grid-cols-2 sm:grid-cols-4 gap-3">
          <!-- Total -->
          <div class="bg-white rounded-2xl border border-slate-200 px-4 py-4 text-center">
            <p class="text-3xl font-heading font-bold text-text tabular-nums">{{ queueStats.total }}</p>
            <p class="text-xs text-slate-500 mt-1">Total</p>
          </div>
          <!-- Waiting -->
          <div class="bg-white rounded-2xl border border-slate-200 px-4 py-4 text-center">
            <p class="text-3xl font-heading font-bold text-amber-500 tabular-nums">{{ queueStats.waiting }}</p>
            <p class="text-xs text-slate-500 mt-1">Waiting</p>
          </div>
          <!-- Checked In -->
          <div class="bg-white rounded-2xl border border-slate-200 px-4 py-4 text-center">
            <p class="text-3xl font-heading font-bold text-emerald-500 tabular-nums">{{ queueStats.checkedIn }}</p>
            <p class="text-xs text-slate-500 mt-1">Checked In</p>
          </div>
          <!-- Called -->
          <div class="bg-white rounded-2xl border border-slate-200 px-4 py-4 text-center">
            <p class="text-3xl font-heading font-bold text-primary tabular-nums">{{ queueStats.called }}</p>
            <p class="text-xs text-slate-500 mt-1">Called</p>
          </div>
        </div>
      </section>

      <!-- ─── Queue List ──────────────────────────────────────────────── -->
      <section aria-labelledby="queue-heading">
        <h2 id="queue-heading" class="text-xs font-semibold uppercase tracking-widest text-slate-400 mb-3">
          Patient Queue
        </h2>

        <!-- Loading skeleton -->
        <div v-if="loading" class="space-y-3">
          <div v-for="i in 4" :key="i" class="bg-white rounded-2xl border border-slate-200 p-4 animate-pulse">
            <div class="flex justify-between items-center">
              <div class="space-y-2">
                <div class="h-4 w-24 bg-slate-100 rounded" />
                <div class="h-3 w-32 bg-slate-100 rounded" />
              </div>
              <div class="h-6 w-16 bg-slate-100 rounded-full" />
            </div>
          </div>
        </div>

        <!-- Empty queue -->
        <div
          v-else-if="queue.length === 0"
          class="bg-white rounded-2xl border border-slate-200 p-8 text-center"
        >
          <div class="w-14 h-14 rounded-2xl bg-primary/8 flex items-center justify-center mx-auto mb-4">
            <svg class="w-7 h-7 text-primary" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.75" aria-hidden="true">
              <path stroke-linecap="round" stroke-linejoin="round"
                d="M18 18.72a9.094 9.094 0 0 0 3.741-.479 3 3 0 0 0-4.682-2.72m.94 3.198.001.031c0 .225-.012.447-.037.666A11.944 11.944 0 0 1 12 21c-2.17 0-4.207-.576-5.963-1.584A6.062 6.062 0 0 1 6 18.719m12 0a5.971 5.971 0 0 0-.941-3.197m0 0A5.995 5.995 0 0 0 12 12.75a5.995 5.995 0 0 0-5.058 2.772m0 0a3 3 0 0 0-4.681 2.72 8.986 8.986 0 0 0 3.74.477m.94-3.197a5.971 5.971 0 0 0-.94 3.197M15 6.75a3 3 0 1 1-6 0 3 3 0 0 1 6 0Zm6 3a2.25 2.25 0 1 1-4.5 0 2.25 2.25 0 0 1 4.5 0Zm-13.5 0a2.25 2.25 0 1 1-4.5 0 2.25 2.25 0 0 1 4.5 0Z" />
            </svg>
          </div>
          <p class="font-heading font-semibold text-text text-base">Queue is empty</p>
          <p class="text-slate-500 text-sm mt-1">No patients in the queue right now.</p>
        </div>

        <!-- Queue rows -->
        <div v-else class="space-y-3">
          <div
            v-for="entry in queue"
            :key="entry.appointment_id"
            class="bg-white rounded-2xl border border-slate-200 overflow-hidden"
          >
            <div class="flex">
              <!-- Status accent bar -->
              <div class="w-1 shrink-0" :class="statusBadge(entry.status).accent" />

              <div class="flex-1 px-5 py-4">
                <!-- Top row -->
                <div class="flex items-start justify-between gap-4">
                  <!-- Left: queue number + short ID -->
                  <div>
                    <p class="font-heading font-bold text-2xl text-text leading-none tabular-nums">
                      #{{ entry.queue_number }}
                    </p>
                    <p class="text-xs text-slate-400 mt-1 font-mono tracking-wide">
                      {{ entry.appointment_id.slice(0, 8).toUpperCase() }}
                    </p>
                  </div>

                  <!-- Right: ETA pill + status badge -->
                  <div class="shrink-0 flex items-center gap-2">
                    <span
                      v-if="entry.status === 'checked_in'"
                      class="inline-flex items-center gap-1 px-2.5 py-1 rounded-full bg-emerald-500 text-white text-xs font-bold tabular-nums"
                    >
                      <svg class="w-3 h-3" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true">
                        <path stroke-linecap="round" stroke-linejoin="round" d="M12 6v6h4.5m4.5 0a9 9 0 1 1-18 0 9 9 0 0 1 18 0Z" />
                      </svg>
                      {{ etaMinutes(entry) }} min
                    </span>
                    <span
                      class="text-xs font-semibold px-2.5 py-1 rounded-full"
                      :class="statusBadge(entry.status).classes"
                    >
                      {{ statusBadge(entry.status).label }}
                    </span>
                  </div>
                </div>

                <!-- Action buttons -->
                <div class="flex items-center justify-between gap-2 mt-4 pt-3 border-t border-slate-100">
                  <!-- Primary actions -->
                  <div class="flex flex-wrap gap-2">
                    <!-- Check In -->
                    <button
                      v-if="entry.status === 'waiting'"
                      type="button"
                      class="inline-flex items-center gap-1.5 px-3 py-1.5 text-xs font-semibold rounded-lg bg-emerald-500 text-white hover:bg-emerald-600 transition-colors duration-150 cursor-pointer disabled:opacity-50"
                      :disabled="actionLoadingId === entry.appointment_id"
                      @click="handleCheckIn(entry.appointment_id)"
                    >
                      <svg class="w-3.5 h-3.5" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true">
                        <path stroke-linecap="round" stroke-linejoin="round" d="M9 12.75 11.25 15 15 9.75M21 12a9 9 0 1 1-18 0 9 9 0 0 1 18 0Z" />
                      </svg>
                      Check In
                    </button>

                    <!-- View Patient -->
                    <button
                      v-if="entry.patient_id"
                      type="button"
                      class="inline-flex items-center gap-1.5 px-3 py-1.5 text-xs font-semibold rounded-lg bg-slate-100 text-slate-700 hover:bg-slate-200 transition-colors duration-150 cursor-pointer"
                      @click="handleViewPatient(entry.patient_id)"
                    >
                      <svg class="w-3.5 h-3.5" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true">
                        <path stroke-linecap="round" stroke-linejoin="round" d="M15.75 6a3.75 3.75 0 1 1-7.5 0 3.75 3.75 0 0 1 7.5 0ZM4.501 20.118a7.5 7.5 0 0 1 14.998 0A17.933 17.933 0 0 1 12 21.75c-2.676 0-5.216-.584-7.499-1.632Z" />
                      </svg>
                      Patient
                    </button>

                    <!-- Deprioritize -->
                    <button
                      v-if="entry.status === 'waiting' || entry.status === 'checked_in'"
                      type="button"
                      class="inline-flex items-center gap-1.5 px-3 py-1.5 text-xs font-semibold rounded-lg bg-slate-100 text-slate-600 hover:bg-slate-200 transition-colors duration-150 cursor-pointer disabled:opacity-50"
                      :disabled="actionLoadingId === entry.appointment_id"
                      @click="handleDeprioritize(entry.appointment_id)"
                    >
                      <svg class="w-3.5 h-3.5" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true">
                        <path stroke-linecap="round" stroke-linejoin="round" d="M3 4.5h14.25M3 9h9.75M3 13.5h9.75m4.5-4.5v12m0 0-3.75-3.75M17.25 21 21 17.25" />
                      </svg>
                      Deprioritize
                    </button>
                  </div>

                  <!-- Destructive actions -->
                  <div class="flex gap-2">
                    <!-- No Show -->
                    <button
                      v-if="entry.status === 'waiting' || entry.status === 'checked_in'"
                      type="button"
                      class="inline-flex items-center gap-1.5 px-3 py-1.5 text-xs font-semibold rounded-lg text-amber-600 hover:bg-amber-50 transition-colors duration-150 cursor-pointer disabled:opacity-50"
                      :disabled="actionLoadingId === entry.appointment_id"
                      @click="handleNoShow(entry.appointment_id)"
                    >
                      <svg class="w-3.5 h-3.5" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true">
                        <path stroke-linecap="round" stroke-linejoin="round" d="M12 9v3.75m9-.75a9 9 0 1 1-18 0 9 9 0 0 1 18 0Zm-9 3.75h.008v.008H12v-.008Z" />
                      </svg>
                      No Show
                    </button>

                    <!-- Remove -->
                    <button
                      type="button"
                      class="inline-flex items-center gap-1.5 px-3 py-1.5 text-xs font-semibold rounded-lg text-red-500 hover:bg-red-50 transition-colors duration-150 cursor-pointer disabled:opacity-50"
                      :disabled="actionLoadingId === entry.appointment_id"
                      @click="handleRemove(entry.appointment_id)"
                    >
                      <svg class="w-3.5 h-3.5" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true">
                        <path stroke-linecap="round" stroke-linejoin="round" d="m14.74 9-.346 9m-4.788 0L9.26 9m9.968-3.21c.342.052.682.107 1.022.166m-1.022-.165L18.16 19.673a2.25 2.25 0 0 1-2.244 2.077H8.084a2.25 2.25 0 0 1-2.244-2.077L4.772 5.79m14.456 0a48.108 48.108 0 0 0-3.478-.397m-12 .562c.34-.059.68-.114 1.022-.165m0 0a48.11 48.11 0 0 1 3.478-.397m7.5 0v-.916c0-1.18-.91-2.164-2.09-2.201a51.964 51.964 0 0 0-3.32 0c-1.18.037-2.09 1.022-2.09 2.201v.916m7.5 0a48.667 48.667 0 0 0-7.5 0" />
                      </svg>
                      Remove
                    </button>
                  </div>
                </div>
              </div>
            </div>
          </div>
        </div>
      </section>

      <!-- ─── Doctors on Duty ─────────────────────────────────────────── -->
      <section aria-labelledby="doctors-heading">
        <h2 id="doctors-heading" class="text-xs font-semibold uppercase tracking-widest text-slate-400 mb-3">
          Doctors on Duty
        </h2>

        <div v-if="loading" class="space-y-3">
          <div v-for="i in 2" :key="i" class="bg-white rounded-2xl border border-slate-200 p-4 animate-pulse">
            <div class="h-4 w-32 bg-slate-100 rounded" />
          </div>
        </div>

        <div v-else-if="doctors.length === 0" class="bg-white rounded-2xl border border-slate-200 p-6 text-center">
          <p class="text-sm text-slate-500">No doctors listed.</p>
        </div>

        <div v-else class="space-y-3">
          <div
            v-for="doctor in doctors"
            :key="doctor.id"
            class="bg-white rounded-2xl border border-slate-200 px-5 py-4 flex items-center justify-between gap-3"
          >
            <div>
              <p class="font-semibold text-sm text-text">{{ doctor.name }}</p>
              <p class="text-xs text-slate-500 mt-0.5">{{ doctor.specialisation }}</p>
            </div>
            <span class="text-xs font-medium px-2.5 py-1 rounded-full bg-emerald-100 text-emerald-700">
              On Duty
            </span>
          </div>
        </div>
      </section>

      <!-- ─── Pending Billing ──────────────────────────────────────────── -->
      <section aria-labelledby="billing-heading">
        <h2 id="billing-heading" class="text-xs font-semibold uppercase tracking-widest text-slate-400 mb-3">
          Pending Billing
        </h2>

        <!-- Billing success -->
        <div
          v-if="billingSuccess"
          role="status"
          class="mb-3 px-4 py-3 bg-emerald-50 border border-emerald-200 rounded-lg text-sm text-emerald-700"
        >
          {{ billingSuccess }}
        </div>

        <!-- Loading -->
        <div v-if="billingLoading" class="space-y-3">
          <div v-for="i in 2" :key="i" class="bg-white rounded-2xl border border-slate-200 p-4 animate-pulse">
            <div class="h-4 w-48 bg-slate-100 rounded" />
          </div>
        </div>

        <!-- Empty -->
        <div
          v-else-if="pendingBilling.length === 0"
          class="bg-white rounded-2xl border border-slate-200 p-6 text-center"
        >
          <p class="text-sm text-slate-500">No consultations awaiting billing.</p>
        </div>

        <!-- Billing rows -->
        <div v-else class="space-y-3">
          <div
            v-for="appt in pendingBilling"
            :key="appt.id"
            class="bg-white rounded-2xl border border-slate-200 overflow-hidden"
          >
            <!-- Summary row — click to expand -->
            <button
              type="button"
              class="w-full text-left px-5 py-4 flex items-center justify-between gap-4 hover:bg-slate-50 transition-colors cursor-pointer"
              @click="toggleBillingExpand(appt.id)"
            >
              <div class="min-w-0">
                <p class="font-heading font-semibold text-sm text-text truncate">
                  Appointment {{ appt.id.slice(0, 8).toUpperCase() }}
                </p>
                <p class="text-xs text-slate-500 mt-0.5">
                  Patient: {{ appt.patient_id?.slice(0, 8) ?? '—' }}
                  <span v-if="appt.date"> · {{ appt.date }}</span>
                </p>
              </div>
              <div class="flex items-center gap-2 shrink-0">
                <span class="text-xs font-semibold px-2.5 py-1 rounded-full bg-amber-100 text-amber-700">
                  Awaiting Billing
                </span>
                <svg
                  class="w-4 h-4 text-slate-400 transition-transform duration-200"
                  :class="{ 'rotate-180': expandedBillingId === appt.id }"
                  viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true"
                >
                  <path stroke-linecap="round" stroke-linejoin="round" d="m19.5 8.25-7.5 7.5-7.5-7.5" />
                </svg>
              </div>
            </button>

            <!-- Expanded detail -->
            <div v-if="expandedBillingId === appt.id" class="border-t border-slate-100 px-5 py-4 space-y-4">

              <!-- Prescription / MC memos -->
              <div>
                <p class="text-xs font-semibold uppercase tracking-wide text-slate-400 mb-2">Prescription &amp; MC</p>
                <div v-if="!prescriptionMap[appt.id]" class="text-xs text-slate-400 animate-pulse">Loading...</div>
                <div v-else-if="prescriptionMap[appt.id].length === 0" class="text-xs text-slate-400">
                  No prescription or MC recorded for this consultation.
                </div>
                <div v-else class="space-y-2">
                  <div
                    v-for="memo in prescriptionMap[appt.id]"
                    :key="memo.id"
                    class="bg-slate-50 rounded-xl px-4 py-3"
                  >
                    <p class="text-xs font-semibold text-slate-600 capitalize">{{ memo.record_type }}</p>
                    <p class="text-sm text-text mt-1 whitespace-pre-wrap">{{ memo.content }}</p>
                  </div>
                </div>
              </div>

              <!-- Amount input -->
              <div>
                <p class="text-xs font-semibold uppercase tracking-wide text-slate-400 mb-2">Billing Amount (SGD)</p>
                <div class="flex items-center gap-3">
                  <div class="relative flex-1 max-w-[200px]">
                    <span class="absolute left-3 top-1/2 -translate-y-1/2 text-sm text-slate-400">$</span>
                    <input
                      type="number"
                      min="0"
                      step="0.01"
                      class="w-full pl-7 pr-3 py-2 border border-slate-200 rounded-lg text-sm text-text focus:outline-none focus:ring-2 focus:ring-primary/30 focus:border-primary"
                      :value="(billingAmounts[appt.id] ?? BASE_CONSULT_CENTS) / 100"
                      @input="billingAmounts[appt.id] = Math.max(0, Math.round(parseFloat($event.target.value || 0) * 100))"
                    />
                  </div>
                  <span class="text-xs text-slate-400">
                    Base: {{ formatDollars(BASE_CONSULT_CENTS) }}
                  </span>
                </div>
              </div>

              <!-- Submit button -->
              <div class="flex items-center justify-end gap-3 pt-2">
                <button
                  type="button"
                  class="inline-flex items-center gap-1.5 px-4 py-2 text-sm font-semibold rounded-lg bg-primary text-white hover:bg-primary/90 transition-colors cursor-pointer disabled:opacity-50"
                  :disabled="billingSubmitting === appt.id || (billingAmounts[appt.id] ?? BASE_CONSULT_CENTS) <= 0"
                  @click="handleSubmitBilling(appt)"
                >
                  <svg v-if="billingSubmitting === appt.id" class="w-4 h-4 animate-spin" viewBox="0 0 24 24" fill="none" aria-hidden="true">
                    <circle cx="12" cy="12" r="10" stroke="currentColor" stroke-width="3" class="opacity-25" />
                    <path fill="currentColor" class="opacity-75" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4z" />
                  </svg>
                  <svg v-else class="w-4 h-4" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true">
                    <path stroke-linecap="round" stroke-linejoin="round" d="M2.25 18.75a60.07 60.07 0 0 1 15.797 2.101c.727.198 1.453-.342 1.453-1.096V18.75M3.75 4.5v.75A.75.75 0 0 1 3 6h-.75m0 0v-.375c0-.621.504-1.125 1.125-1.125H20.25M2.25 6v9m18-10.5v.75c0 .414.336.75.75.75h.75m-1.5-1.5h.375c.621 0 1.125.504 1.125 1.125v9.75c0 .621-.504 1.125-1.125 1.125h-.375m1.5-1.5H21a.75.75 0 0 0-.75.75v.75m0 0H3.75m0 0h-.375a1.125 1.125 0 0 1-1.125-1.125V15m1.5 1.5v-.75A.75.75 0 0 0 3 15h-.75M15 10.5a3 3 0 1 1-6 0 3 3 0 0 1 6 0Zm3 0h.008v.008H18V10.5Zm-12 0h.008v.008H6V10.5Z" />
                  </svg>
                  Submit Billing
                </button>
              </div>
            </div>
          </div>
        </div>
      </section>

    </main>

    <!-- ─── Patient Profile Modal ─────────────────────────────────────── -->
    <div
      v-if="showPatientModal"
      class="fixed inset-0 z-50 flex items-end sm:items-center justify-center p-4 bg-black/40"
      @click.self="showPatientModal = false"
    >
      <div class="bg-white rounded-2xl w-full max-w-md max-h-[80vh] overflow-y-auto shadow-xl">

        <div class="sticky top-0 bg-white border-b border-slate-100 px-5 py-4 flex items-center justify-between">
          <h3 class="font-heading font-semibold text-text">Patient Profile</h3>
          <button
            type="button"
            class="text-slate-400 hover:text-text transition-colors cursor-pointer"
            aria-label="Close"
            @click="showPatientModal = false"
          >
            <svg class="w-5 h-5" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true">
              <path stroke-linecap="round" stroke-linejoin="round" d="M6 18 18 6M6 6l12 12" />
            </svg>
          </button>
        </div>

        <div class="p-5">
          <!-- Loading -->
          <div v-if="patientLoading" class="space-y-3 animate-pulse">
            <div class="h-5 w-32 bg-slate-100 rounded" />
            <div class="h-4 w-48 bg-slate-100 rounded" />
            <div class="h-4 w-40 bg-slate-100 rounded" />
          </div>

          <!-- Patient info -->
          <div v-else-if="selectedPatient">
            <div class="flex items-center gap-3 mb-4">
              <div class="w-12 h-12 rounded-full bg-primary/10 flex items-center justify-center shrink-0">
                <svg class="w-6 h-6 text-primary" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.75" aria-hidden="true">
                  <path stroke-linecap="round" stroke-linejoin="round"
                    d="M15.75 6a3.75 3.75 0 1 1-7.5 0 3.75 3.75 0 0 1 7.5 0ZM4.501 20.118a7.5 7.5 0 0 1 14.998 0A17.933 17.933 0 0 1 12 21.75c-2.676 0-5.216-.584-7.499-1.632Z" />
                </svg>
              </div>
              <div>
                <p class="font-heading font-semibold text-text">{{ selectedPatient.nric }}</p>
                <p class="text-sm text-slate-500">
                  {{ formatGender(selectedPatient.gender) }} · DOB: {{ formatDOB(selectedPatient.dob) }}
                </p>
                <p class="text-sm text-slate-500">{{ selectedPatient.phone ?? '—' }}</p>
              </div>
            </div>

            <!-- Allergies -->
            <div
              v-if="selectedPatient.allergies?.length"
              class="bg-amber-50 border border-amber-200 rounded-xl px-4 py-3"
            >
              <p class="text-xs font-semibold text-amber-700 uppercase tracking-wide mb-1.5">Allergies</p>
              <div class="flex flex-wrap gap-1.5">
                <span
                  v-for="allergy in selectedPatient.allergies"
                  :key="allergy"
                  class="text-xs px-2 py-0.5 bg-amber-100 text-amber-800 rounded-full font-medium"
                >
                  {{ allergy }}
                </span>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>

  </div>
</template>
