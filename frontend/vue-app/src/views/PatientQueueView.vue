<script setup>
import { ref, onMounted, onUnmounted, computed } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { useAppointment, calculateEtaMinutes } from '@/composables/useAppointment'
import { useAuthStore } from '@/stores/auth'

const route = useRoute()
const router = useRouter()
const authStore = useAuthStore()
const { connectQueueWebSocket } = useAppointment()

const API = import.meta.env.VITE_API_BASE_URL ?? ''

// ── State ──
const queuePosition = ref(null) // { queue_number, estimated_time, status }
const loading = ref(true)
const error = ref('')
let wsHandle = null

const appointmentId = route.params.appointmentId

// ── Computed display values ──
const positionText = computed(() => {
  if (!queuePosition.value) return null
  const pos = queuePosition.value.queue_number
  if (pos <= 0) return "You're next!"
  if (pos === 1) return '1 person in front of you'
  return `${pos} persons in front of you`
})

const etaText = computed(() => {
  if (!queuePosition.value) return null
  const minutes = calculateEtaMinutes(queuePosition.value.estimated_time)
  if (minutes === null || minutes === 0) return 'Any moment now'
  return `ETA ${minutes} minutes to your turn`
})

const statusLabel = computed(() => {
  if (!queuePosition.value) return ''
  const map = {
    waiting: 'In Queue',
    checked_in: 'Checked In',
    called: 'Your Turn!',
    in_progress: 'With Doctor',
    completed: 'Done',
    no_show: 'Missed',
  }
  return map[queuePosition.value.status] || queuePosition.value.status
})

const statusColor = computed(() => {
  if (!queuePosition.value) return 'bg-gray-100 text-gray-600'
  const map = {
    waiting: 'bg-amber-100 text-amber-800',
    checked_in: 'bg-amber-100 text-amber-800',
    called: 'bg-emerald-100 text-emerald-800',
    in_progress: 'bg-primary/10 text-primary',
    completed: 'bg-gray-100 text-gray-600',
    no_show: 'bg-red-100 text-red-700',
  }
  return map[queuePosition.value.status] || 'bg-gray-100 text-gray-600'
})

// ── REST fetch (initial load) ──
async function fetchQueuePosition() {
  try {
    const res = await fetch(`${API}/api/queue/position/${appointmentId}`, {
      headers: { Authorization: `Bearer ${authStore.jwt}` },
    })
    if (!res.ok) throw new Error('Failed to fetch queue position')
    queuePosition.value = await res.json()
  } catch (e) {
    error.value = e.message
  } finally {
    loading.value = false
  }
}

// ── Lifecycle ──
onMounted(async () => {
  if (!appointmentId) {
    loading.value = false
    error.value = 'No active appointment found. Please check in first.'
    return
  }

  await fetchQueuePosition()

  // Live updates via the shared composable (handles reconnect + auth)
  wsHandle = connectQueueWebSocket(appointmentId, (entry) => {
    queuePosition.value = entry
    loading.value = false
    if (entry.status === 'done' || entry.status === 'cancelled') {
      wsHandle?.close()
      router.push('/dashboard')
    }
  })
})

onUnmounted(() => wsHandle?.close())
</script>

<template>
  <div class="min-h-dvh bg-surface">

    <!-- Top nav (matches dashboard) -->
    <header class="sticky top-0 z-20 bg-white border-b border-slate-200">
      <div class="max-w-2xl mx-auto px-4 h-14 flex items-center gap-3">
        <button
          type="button"
          class="flex items-center gap-1.5 text-sm text-slate-500 hover:text-text transition-colors duration-150 cursor-pointer"
          @click="router.push('/dashboard')"
        >
          <svg class="w-4 h-4" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true">
            <path stroke-linecap="round" stroke-linejoin="round" d="M15.75 19.5 8.25 12l7.5-7.5" />
          </svg>
          Back
        </button>
        <span class="font-heading font-semibold text-text text-sm">Queue Status</span>
      </div>
    </header>

    <main class="max-w-2xl mx-auto px-4 py-8">

      <!-- Loading skeleton -->
      <div v-if="loading" class="bg-white rounded-2xl border border-slate-200 p-8 animate-pulse space-y-4" aria-busy="true">
        <div class="h-6 w-24 bg-slate-100 rounded-full mx-auto" />
        <div class="h-16 w-20 bg-slate-100 rounded mx-auto" />
        <div class="h-5 w-48 bg-slate-100 rounded mx-auto" />
        <div class="h-6 w-40 bg-slate-100 rounded mx-auto" />
      </div>

      <!-- Error -->
      <div
        v-else-if="error"
        class="bg-white rounded-2xl border border-slate-200 p-8 text-center"
        role="alert"
      >
        <p class="text-slate-500 text-sm">{{ error }}</p>
        <button
          type="button"
          class="mt-4 px-4 py-2 bg-primary text-white text-sm font-semibold rounded-xl hover:bg-primary/90 transition-colors cursor-pointer"
          @click="router.push('/dashboard')"
        >
          Go to Dashboard
        </button>
      </div>

      <!-- Queue Card -->
      <div v-else-if="queuePosition" class="bg-white rounded-2xl border border-slate-200 overflow-hidden">
        <!-- Status badge -->
        <div class="px-6 pt-6 pb-4 text-center border-b border-slate-100">
          <span class="px-3 py-1 rounded-full text-xs font-semibold" :class="statusColor">
            {{ statusLabel }}
          </span>
        </div>

        <!-- Main position display -->
        <div class="p-8 text-center space-y-2">
          <div class="text-7xl font-heading font-bold text-text tabular-nums leading-none">
            {{ queuePosition.queue_number }}
          </div>
          <p class="text-base text-slate-600">
            {{ positionText }}
          </p>
          <p class="text-xl font-semibold text-primary pt-1">
            {{ etaText }}
          </p>
        </div>

        <!-- Live indicator -->
        <div class="px-6 pb-6 text-center">
          <div class="flex items-center justify-center gap-2 text-xs text-slate-400">
            <span class="relative flex h-2 w-2">
              <span class="animate-ping absolute inline-flex h-full w-full rounded-full bg-emerald-400 opacity-75" />
              <span class="relative inline-flex rounded-full h-2 w-2 bg-emerald-500" />
            </span>
            Live updates
          </div>
        </div>
      </div>

    </main>
  </div>
</template>
