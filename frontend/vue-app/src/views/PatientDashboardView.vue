<script setup>
import { ref, computed, watch, onMounted, onUnmounted } from 'vue'
import { useRouter } from 'vue-router'
import { useAuthStore } from '@/stores/auth'
import { useAuth } from '@/composables/useAuth'
import { useAppointment, mapQueueEntry } from '@/composables/useAppointment'

const router = useRouter()
const authStore = useAuthStore()
const { signOut } = useAuth()
const { fetchDashboardData, connectQueueWebSocket, checkIn: apiCheckIn } = useAppointment()

// ─── State ──────────────────────────────────────────────────────────────────
const loading = ref(true)
const fetchError = ref('')   // background load failure — shown when no card to display
const actionError = ref('')  // button action failure — shown inline inside the card
const appointment = ref(null)

let wsConnection = null  // WS handle returned by connectQueueWebSocket
let fallbackTimer = null // slow 60 s poll as a safety net in case WS drops

async function loadDashboard() {
  try {
    appointment.value = await fetchDashboardData()
    fetchError.value = ''
  } catch {
    fetchError.value = 'Could not load your appointment. Please refresh.'
  } finally {
    loading.value = false
  }
}

// Apply a live queue push from the WebSocket without a full re-fetch
function applyQueueUpdate(entry) {
  if (!appointment.value || entry.appointment_id !== appointment.value.id) return
  if (entry.status === 'done' || entry.status === 'cancelled') {
    wsConnection?.close()
    wsConnection = null
    appointment.value = null
    return
  }
  appointment.value = mapQueueEntry(appointment.value, entry)
}

// Open (or re-open) WS whenever the appointment id changes
watch(
  () => appointment.value?.id,
  (id) => {
    wsConnection?.close()
    wsConnection = null
    if (id) {
      wsConnection = connectQueueWebSocket(id, applyQueueUpdate)
    }
  },
)

// 60 s fallback poll — catches appointment status changes that don't come via WS
// (e.g. the appointment-service flipping in_progress once the doctor opens the record)
const FALLBACK_POLL_MS = 60_000

onMounted(() => {
  loadDashboard()
  fallbackTimer = setInterval(loadDashboard, FALLBACK_POLL_MS)
})

onUnmounted(() => {
  wsConnection?.close()
  clearInterval(fallbackTimer)
})

// ─── Derived ─────────────────────────────────────────────────────────────────
const greeting = computed(() => {
  const h = new Date().getHours()
  if (h < 12) return 'Good morning'
  if (h < 18) return 'Good afternoon'
  return 'Good evening'
})

const firstName = computed(() => authStore.user?.name?.split(' ')[0] ?? 'there')

const checkInLabel = computed(() => {
  if (!appointment.value) return ''
  const map = { waiting: 'Check In', checked_in: 'Checked In', called: 'Your Turn — Go In' }
  return map[appointment.value.status] ?? 'Check In'
})

const statusBadge = computed(() => {
  if (!appointment.value) return null
  const map = {
    waiting:    { label: 'Waiting',    classes: 'bg-amber-100 text-amber-800' },
    checked_in: { label: 'Checked In', classes: 'bg-emerald-100 text-emerald-800' },
    called:     { label: 'Called',     classes: 'bg-primary/10 text-primary' },
  }
  return map[appointment.value.status] ?? null
})

// ─── Handlers ────────────────────────────────────────────────────────────────
async function handleCheckIn() {
  if (!appointment.value || appointment.value.status === 'checked_in' || appointment.value.status === 'called') return
  actionError.value = ''
  try {
    const entry = await apiCheckIn(appointment.value.id)
    appointment.value = mapQueueEntry(appointment.value, entry)
  } catch (e) {
    actionError.value = e.message === 'Appointment not in queue'
      ? 'Your place in the queue is being set up — please try again in a moment.'
      : (e.message ?? 'Check-in failed. Please try again.')
  }
}
</script>

<template>
  <div class="min-h-dvh bg-surface">

    <!-- ─── Top Navigation ────────────────────────────────────────────────── -->
    <header class="sticky top-0 z-20 bg-white border-b border-slate-200">
      <div class="max-w-2xl mx-auto px-4 h-14 flex items-center justify-between">
        <!-- Clinic logo mark -->
        <div class="flex items-center gap-2">
          <!-- Plus / cross icon -->
          <svg class="w-6 h-6 text-primary" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true">
            <path fill-rule="evenodd"
              d="M12 2.25a.75.75 0 0 1 .75.75v8.25H21a.75.75 0 0 1 0 1.5h-8.25V21a.75.75 0 0 1-1.5 0v-8.25H3a.75.75 0 0 1 0-1.5h8.25V3a.75.75 0 0 1 .75-.75Z"
              clip-rule="evenodd" />
          </svg>
          <span class="font-heading font-semibold text-text text-sm tracking-tight">SmartClinic</span>
        </div>

        <!-- User + sign out -->
        <div class="flex items-center gap-3">
          <span class="text-sm text-slate-500 hidden sm:inline">{{ authStore.user?.name }}</span>
          <button
            type="button"
            class="flex items-center gap-1.5 text-sm text-slate-500 hover:text-text transition-colors duration-150 cursor-pointer"
            aria-label="Sign out"
            @click="signOut"
          >
            <!-- ArrowRightOnRectangle -->
            <svg class="w-5 h-5" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.75" aria-hidden="true">
              <path stroke-linecap="round" stroke-linejoin="round"
                d="M15.75 9V5.25A2.25 2.25 0 0 0 13.5 3h-6a2.25 2.25 0 0 0-2.25 2.25v13.5A2.25 2.25 0 0 0 7.5 21h6a2.25 2.25 0 0 0 2.25-2.25V15M18 15l3-3m0 0-3-3m3 3H9" />
            </svg>
            <span class="sr-only sm:not-sr-only">Sign out</span>
          </button>
        </div>
      </div>
    </header>

    <!-- ─── Main content ──────────────────────────────────────────────────── -->
    <main class="max-w-2xl mx-auto px-4 py-8 space-y-8">

      <!-- Greeting -->
      <div>
        <p class="text-sm text-slate-500 font-body">{{ greeting }},</p>
        <h1 class="font-heading font-semibold text-2xl text-text">{{ firstName }}</h1>
      </div>

      <!-- ─── Next Appointment Card ──────────────────────────────────────── -->
      <!-- aria-live="polite" announces appointment data once it loads -->
      <section aria-labelledby="next-appt-heading" aria-live="polite" aria-atomic="false">
        <h2 id="next-appt-heading" class="text-xs font-semibold uppercase tracking-widest text-slate-400 mb-3">
          Next Appointment
        </h2>

        <!-- Load error — only shown when there is no appointment card to display -->
        <div
          v-if="fetchError && !appointment"
          role="alert"
          class="px-4 py-3 bg-red-50 border border-red-200 rounded-xl text-sm text-red-700"
        >
          {{ fetchError }}
        </div>

        <!-- Loading skeleton -->
        <div v-if="!fetchError && loading" class="bg-white rounded-2xl border border-slate-200 p-5 space-y-4 animate-pulse" aria-busy="true" aria-label="Loading appointment details">
          <div class="flex justify-between">
            <div class="h-5 w-40 bg-slate-100 rounded" />
            <div class="h-5 w-16 bg-slate-100 rounded-full" />
          </div>
          <div class="h-4 w-28 bg-slate-100 rounded" />
          <div class="flex gap-4 pt-1">
            <div class="h-10 w-20 bg-slate-100 rounded-xl" />
            <div class="h-10 w-20 bg-slate-100 rounded-xl" />
            <div class="h-10 w-20 bg-slate-100 rounded-xl" />
          </div>
          <div class="h-px bg-slate-100" />
          <div class="h-4 w-48 bg-slate-100 rounded" />
          <div class="h-4 w-36 bg-slate-100 rounded" />
          <div class="h-11 w-full bg-slate-100 rounded-xl mt-2" />
        </div>

        <!-- No appointment empty state -->
        <div
          v-else-if="!fetchError && !appointment"
          class="bg-white rounded-2xl border border-slate-200 p-8 text-center"
        >
          <div class="w-14 h-14 rounded-2xl bg-primary/8 flex items-center justify-center mx-auto mb-4">
            <svg class="w-7 h-7 text-primary" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.75" aria-hidden="true">
              <path stroke-linecap="round" stroke-linejoin="round"
                d="M6.75 3v2.25M17.25 3v2.25M3 18.75V7.5a2.25 2.25 0 0 1 2.25-2.25h13.5A2.25 2.25 0 0 1 21 7.5v11.25m-18 0A2.25 2.25 0 0 0 5.25 21h13.5A2.25 2.25 0 0 0 21 18.75m-18 0v-7.5A2.25 2.25 0 0 1 5.25 9h13.5A2.25 2.25 0 0 1 21 11.25v7.5" />
            </svg>
          </div>
          <p class="font-heading font-semibold text-text text-base">No upcoming appointments</p>
          <p class="text-slate-500 text-sm mt-1 text-pretty">Book a visit to get started.</p>
          <button
            type="button"
            class="mt-5 inline-flex items-center gap-2 px-5 py-2.5 bg-cta text-white text-sm font-semibold rounded-xl hover:bg-cta/90 transition-colors duration-150 cursor-pointer focus-visible:outline-3 focus-visible:outline-offset-2 focus-visible:outline-cta"
            @click="router.push('/booking')"
          >
            <svg class="w-4 h-4" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true">
              <path stroke-linecap="round" stroke-linejoin="round" d="M12 4.5v15m7.5-7.5h-15" />
            </svg>
            Book Appointment
          </button>
        </div>

        <!-- Appointment detail card -->
        <div
          v-else-if="appointment"
          class="bg-white rounded-2xl border border-slate-200 overflow-hidden"
        >
          <!-- Coloured left stripe + header -->
          <div class="border-l-4 border-primary px-5 pt-5 pb-4">
            <div class="flex items-start justify-between gap-3">
              <div>
                <p class="font-heading font-semibold text-text text-lg leading-snug">
                  {{ appointment.doctor }}
                </p>
                <p class="text-sm text-slate-500 mt-0.5">{{ appointment.specialty }}</p>
              </div>
              <!-- Status badge -->
              <span
                v-if="statusBadge"
                class="shrink-0 text-xs font-semibold px-2.5 py-1 rounded-full tabular-nums"
                :class="statusBadge.classes"
              >
                {{ statusBadge.label }}
              </span>
            </div>

            <!-- Live queue stats -->
            <div class="mt-4 flex gap-3 flex-wrap" role="group" aria-label="Live queue status">
              <!-- Queue number -->
              <div class="flex flex-col items-center justify-center bg-primary/8 rounded-xl px-4 py-2.5 min-w-18">
                <span class="text-2xl font-heading font-bold text-primary tabular-nums leading-none">
                  {{ appointment.queueNumber != null ? '#' + appointment.queueNumber : '—' }}
                </span>
                <span class="text-[11px] text-slate-500 mt-0.5">Your no.</span>
              </div>

              <!-- ETA — "ahead" count omitted until queue endpoint exposes it -->
              <div class="flex flex-col items-center justify-center bg-slate-50 rounded-xl px-4 py-2.5 min-w-18">
                <span class="text-2xl font-heading font-bold text-text tabular-nums leading-none">
                  {{ appointment.etaMinutes != null ? '~' + appointment.etaMinutes : '—' }}
                </span>
                <span class="text-[11px] text-slate-500 mt-0.5">min wait</span>
              </div>
            </div>
          </div>

          <!-- Date / location -->
          <div class="px-5 py-4 border-t border-slate-100 space-y-2.5">
            <div class="flex items-center gap-2 text-sm text-slate-600">
              <!-- Calendar icon -->
              <svg class="w-4 h-4 text-slate-400 shrink-0" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.75" aria-hidden="true">
                <path stroke-linecap="round" stroke-linejoin="round"
                  d="M6.75 3v2.25M17.25 3v2.25M3 18.75V7.5a2.25 2.25 0 0 1 2.25-2.25h13.5A2.25 2.25 0 0 1 21 7.5v11.25m-18 0A2.25 2.25 0 0 0 5.25 21h13.5A2.25 2.25 0 0 0 21 18.75m-18 0v-7.5A2.25 2.25 0 0 1 5.25 9h13.5A2.25 2.25 0 0 1 21 11.25v7.5" />
              </svg>
              <span>{{ appointment.date }} · {{ appointment.time }}</span>
            </div>

            <div class="flex items-center gap-2 text-sm text-slate-600">
              <!-- Map pin icon -->
              <svg class="w-4 h-4 text-slate-400 shrink-0" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.75" aria-hidden="true">
                <path stroke-linecap="round" stroke-linejoin="round"
                  d="M15 10.5a3 3 0 1 1-6 0 3 3 0 0 1 6 0Z" />
                <path stroke-linecap="round" stroke-linejoin="round"
                  d="M19.5 10.5c0 7.142-7.5 11.25-7.5 11.25S4.5 17.642 4.5 10.5a7.5 7.5 0 1 1 15 0Z" />
              </svg>
              <span>{{ appointment.location }}</span>
            </div>
          </div>

          <!-- Inline action error (check-in failure) -->
          <div
            v-if="actionError"
            role="alert"
            class="mx-5 mb-3 px-3 py-2 bg-red-50 border border-red-200 rounded-lg text-xs text-red-700"
          >
            {{ actionError }}
          </div>

          <!-- Check in CTA.
               aria-disabled keeps non-actionable states focusable for
               keyboard users so they can discover the current status. -->
          <div class="px-5 pb-5 space-y-2">
            <button
              type="button"
              class="w-full h-11 rounded-xl font-semibold text-sm transition-colors duration-150 focus-visible:outline-3 focus-visible:outline-offset-2"
              :class="{
                'bg-cta text-white hover:bg-cta/90 focus-visible:outline-cta cursor-pointer':
                  appointment.status === 'waiting',
                'bg-emerald-50 text-emerald-700 border border-emerald-200 cursor-default':
                  appointment.status === 'checked_in',
                'bg-primary/10 text-primary border border-primary/20 cursor-default':
                  appointment.status === 'called',
              }"
              :aria-disabled="appointment.status !== 'waiting' ? 'true' : undefined"
              @click="handleCheckIn"
            >
              {{ checkInLabel }}
            </button>
            <!-- View Queue button — shown once checked in -->
            <button
              v-if="appointment.status === 'checked_in' || appointment.status === 'called'"
              type="button"
              class="w-full h-11 rounded-xl font-semibold text-sm bg-white border border-slate-200 text-slate-700 hover:border-primary hover:text-primary transition-colors duration-150 cursor-pointer focus-visible:outline-3 focus-visible:outline-offset-2 focus-visible:outline-primary"
              @click="router.push(`/queue/${appointment.id}`)"
            >
              View Queue Status
            </button>
          </div>
        </div>
      </section>

      <!-- ─── Quick Actions ──────────────────────────────────────────────── -->
      <section aria-labelledby="actions-heading">
        <h2 id="actions-heading" class="text-xs font-semibold uppercase tracking-widest text-slate-400 mb-3">
          Quick Actions
        </h2>

        <div class="grid grid-cols-1 sm:grid-cols-3 gap-3">
          <!-- Book appointment -->
          <button
            type="button"
            class="group bg-white border border-slate-200 rounded-2xl px-4 py-5 text-left hover:border-primary hover:shadow-sm transition-all duration-150 cursor-pointer focus-visible:outline-3 focus-visible:outline-offset-2 focus-visible:outline-primary"
            aria-label="Book a new appointment"
            @click="router.push('/booking')"
          >
            <div class="w-10 h-10 rounded-xl bg-primary/8 flex items-center justify-center mb-3 group-hover:bg-primary/12 transition-colors duration-150">
              <!-- CalendarDays + Plus -->
              <svg class="w-5 h-5 text-primary" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.75" aria-hidden="true">
                <path stroke-linecap="round" stroke-linejoin="round"
                  d="M6.75 3v2.25M17.25 3v2.25M3 18.75V7.5a2.25 2.25 0 0 1 2.25-2.25h13.5A2.25 2.25 0 0 1 21 7.5v11.25m-18 0A2.25 2.25 0 0 0 5.25 21h13.5A2.25 2.25 0 0 0 21 18.75m-18 0v-7.5A2.25 2.25 0 0 1 5.25 9h13.5A2.25 2.25 0 0 1 21 11.25v7.5M12 15.75h.008v.008H12v-.008Zm0-3h.008v.008H12v-.008Zm-3 3h.008v.008H9v-.008Zm0-3h.008v.008H9v-.008Zm6 3h.008v.008H15v-.008Zm0-3h.008v.008H15v-.008Z" />
              </svg>
            </div>
            <p class="font-semibold text-sm text-text text-balance">Book Appointment</p>
            <p class="text-xs text-slate-500 mt-0.5 text-pretty">Schedule a new visit</p>
          </button>

          <!-- Appointment history -->
          <button
            type="button"
            class="group bg-white border border-slate-200 rounded-2xl px-4 py-5 text-left hover:border-primary hover:shadow-sm transition-all duration-150 cursor-pointer focus-visible:outline-3 focus-visible:outline-offset-2 focus-visible:outline-primary"
            aria-label="View appointment history"
          >
            <div class="w-10 h-10 rounded-xl bg-primary/8 flex items-center justify-center mb-3 group-hover:bg-primary/12 transition-colors duration-150">
              <!-- ClockIcon -->
              <svg class="w-5 h-5 text-primary" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.75" aria-hidden="true">
                <path stroke-linecap="round" stroke-linejoin="round" d="M12 6v6h4.5m4.5 0a9 9 0 1 1-18 0 9 9 0 0 1 18 0Z" />
              </svg>
            </div>
            <p class="font-semibold text-sm text-text text-balance">Appointment History</p>
            <p class="text-xs text-slate-500 mt-0.5 text-pretty">Past and upcoming visits</p>
          </button>

          <!-- Medical records -->
          <button
            type="button"
            class="group bg-white border border-slate-200 rounded-2xl px-4 py-5 text-left hover:border-primary hover:shadow-sm transition-all duration-150 cursor-pointer focus-visible:outline-3 focus-visible:outline-offset-2 focus-visible:outline-primary"
            aria-label="View and upload medical records"
            @click="router.push('/records')"
          >
            <div class="w-10 h-10 rounded-xl bg-primary/8 flex items-center justify-center mb-3 group-hover:bg-primary/12 transition-colors duration-150">
              <!-- DocumentText -->
              <svg class="w-5 h-5 text-primary" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.75" aria-hidden="true">
                <path stroke-linecap="round" stroke-linejoin="round"
                  d="M19.5 14.25v-2.625a3.375 3.375 0 0 0-3.375-3.375h-1.5A1.125 1.125 0 0 1 13.5 7.125v-1.5a3.375 3.375 0 0 0-3.375-3.375H8.25m0 12.75h7.5m-7.5 3H12M10.5 2.25H5.625c-.621 0-1.125.504-1.125 1.125v17.25c0 .621.504 1.125 1.125 1.125h12.75c.621 0 1.125-.504 1.125-1.125V11.25a9 9 0 0 0-9-9Z" />
              </svg>
            </div>
            <p class="font-semibold text-sm text-text text-balance">Medical Records</p>
            <p class="text-xs text-slate-500 mt-0.5 text-pretty">Upload notes &amp; documents</p>
          </button>
        </div>
      </section>

    </main>
  </div>
</template>
