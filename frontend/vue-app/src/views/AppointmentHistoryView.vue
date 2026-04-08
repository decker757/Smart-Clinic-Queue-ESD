<script setup>
import { ref, onMounted } from 'vue'
import { useRouter } from 'vue-router'
import { useAuthStore } from '@/stores/auth'

const router = useRouter()
const authStore = useAuthStore()

import { API_BASE } from '@/utils/env'

const appointments = ref([])
const loading = ref(true)
const error = ref('')
const expandedId = ref(null)
const refreshingPayment = ref(null)
const cancellingId = ref(null)

// Lazy-loaded per-patient detail (fetched once on first expand)
const memos = ref(null)       // null = not yet fetched
const history = ref(null)
const payments = ref(null)
const detailLoading = ref(false)

function formatCents(cents, currency = 'SGD') {
  if (cents == null) return ''
  return `$${(cents / 100).toFixed(2)} ${currency.toUpperCase()}`
}

const STATUS_LABEL = {
  scheduled:   'Upcoming',
  checked_in:  'Checked In',
  in_progress: 'In Progress',
  completed:   'Completed',
  cancelled:   'Cancelled',
  no_show:     'No Show',
}

const PAYMENT_BADGE = {
  paid:    { label: 'Paid',    cls: 'bg-green-50 text-green-700' },
  pending: { label: 'Unpaid',  cls: 'bg-amber-50 text-amber-700' },
  failed:  { label: 'Failed',  cls: 'bg-red-50 text-red-600' },
}

const STATUS_CLASS = {
  scheduled:   'bg-blue-50 text-blue-700',
  checked_in:  'bg-teal-50 text-teal-700',
  in_progress: 'bg-yellow-50 text-yellow-700',
  completed:   'bg-green-50 text-green-700',
  cancelled:   'bg-slate-100 text-slate-500',
  no_show:     'bg-red-50 text-red-600',
}

function authHeaders() {
  return { Authorization: `Bearer ${authStore.jwt}` }
}

function formatDate(iso) {
  if (!iso) return 'Date TBD'
  return new Date(iso).toLocaleDateString('en-SG', {
    weekday: 'short', day: 'numeric', month: 'short', year: 'numeric',
  })
}

function formatTime(iso) {
  if (!iso) return null
  return new Date(iso).toLocaleTimeString('en-SG', { hour: '2-digit', minute: '2-digit' })
}

function formatDateShort(iso) {
  if (!iso) return ''
  return new Date(iso).toLocaleDateString('en-SG', { day: 'numeric', month: 'short', year: 'numeric' })
}

function memosByAppt(appt) {
  if (!memos.value) return []
  return memos.value.filter((m) => {
    if (!['mc', 'prescription'].includes(m.record_type)) return false
    // Prefer appointment_id if stored; fall back to 2-hour time window for old records
    if (m.appointment_id) return m.appointment_id === appt.id
    const ref = new Date(appt.updated_at ?? appt.created_at)
    return Math.abs(new Date(m.created_at) - ref) < 2 * 60 * 60 * 1000
  })
}

function historyByAppt(appt) {
  if (!history.value) return []
  const ref = new Date(appt.updated_at ?? appt.created_at)
  return history.value.filter((h) => {
    const t = h.diagnosed_at ?? h.created_at
    return Math.abs(new Date(t) - ref) < 2 * 60 * 60 * 1000
  })
}

async function loadDetail(force = false) {
  if (memos.value !== null && !force) return  // already fetched
  detailLoading.value = true
  const pid = authStore.user?.id
  // Payments are already fetched in loadAll(); only fetch memos + history here
  const [memoRes, histRes] = await Promise.all([
    fetch(`${API_BASE}/api/composite/patients/${pid}/memos`, { headers: authHeaders() }),
    fetch(`${API_BASE}/api/composite/patients/${pid}/history`, { headers: authHeaders() }),
  ])
  memos.value = memoRes.ok ? ((await memoRes.json()) ?? []) : []
  history.value = histRes.ok ? ((await histRes.json()) ?? []) : []
  detailLoading.value = false
}

function paymentByAppt(appt) {
  if (!payments.value) return null
  return payments.value.find(p => p.consultation_id === appt.id) ?? null
}

const cancelTarget = ref(null)

async function confirmCancelAppointment() {
  if (!cancelTarget.value) return
  const appt = cancelTarget.value
  cancellingId.value = appt.id
  try {
    const res = await fetch(
      `${API_BASE}/api/composite/appointments/${appt.id}`,
      { method: 'DELETE', headers: authHeaders() },
    )
    if (res.ok) appt.status = 'cancelled'
  } finally {
    cancellingId.value = null
    cancelTarget.value = null
  }
}

async function payNow(appt) {
  const pid = authStore.user?.id
  refreshingPayment.value = appt.id
  try {
    const res = await fetch(
      `${API_BASE}/api/composite/patients/${pid}/payments/${appt.id}/refresh`,
      { method: 'POST', headers: authHeaders() },
    )
    if (res.ok) {
      const data = await res.json()
      window.open(data.payment_link, '_blank', 'noopener,noreferrer')
      // Update cached payment link
      if (payments.value) {
        const p = payments.value.find(p => p.consultation_id === appt.id)
        if (p) p.payment_link = data.payment_link
      }
    } else {
      const p = paymentByAppt(appt)
      if (p?.payment_link) window.open(p.payment_link, '_blank', 'noopener,noreferrer')
    }
  } finally {
    refreshingPayment.value = null
  }
}

async function toggle(id) {
  if (expandedId.value === id) { expandedId.value = null; return }
  expandedId.value = id
  await loadDetail()
}

async function loadAll() {
  loading.value = true
  error.value = ''
  const pid = authStore.user?.id
  try {
    // Fetch appointments and payments in parallel so payment badges render immediately
    const [apptRes, payRes] = await Promise.all([
      fetch(`${API_BASE}/api/composite/appointments?patient_id=${pid}`, { headers: authHeaders() }),
      fetch(`${API_BASE}/api/composite/patients/${pid}/payments`, { headers: authHeaders() }),
    ])
    if (!apptRes.ok) throw new Error('Failed to load appointments')
    appointments.value = ((await apptRes.json()) ?? []).sort(
      (a, b) => new Date(b.created_at) - new Date(a.created_at),
    )
    payments.value = payRes.ok ? ((await payRes.json()) ?? []) : []
  } catch (e) {
    error.value = e.message ?? 'Could not load appointment history.'
  } finally {
    loading.value = false
  }
}

onMounted(() => {
  if (!authStore.user?.id) { router.push('/login'); return }
  // Reset cached detail so fresh data is loaded when an appointment is expanded
  memos.value = null
  history.value = null
  payments.value = null
  loadAll()
})
</script>

<template>
  <div class="min-h-dvh bg-surface">

    <!-- Header -->
    <header class="sticky top-0 z-20 bg-white border-b border-slate-200">
      <div class="max-w-2xl mx-auto px-4 h-14 flex items-center gap-3">
        <button
          type="button"
          class="flex items-center justify-center w-8 h-8 rounded-lg text-slate-500 hover:text-text hover:bg-slate-100 transition-colors duration-150 cursor-pointer"
          aria-label="Back"
          @click="router.push('/dashboard')"
        >
          <svg class="w-5 h-5" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.75">
            <path stroke-linecap="round" stroke-linejoin="round" d="M15.75 19.5 8.25 12l7.5-7.5" />
          </svg>
        </button>
        <h1 class="font-heading font-semibold text-text text-base">Appointment History</h1>
      </div>
    </header>

    <main class="max-w-2xl mx-auto px-4 py-6">

      <!-- Loading -->
      <div v-if="loading" class="flex justify-center py-16">
        <svg class="w-6 h-6 animate-spin text-primary" viewBox="0 0 24 24" fill="none">
          <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"/>
          <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8v8H4z"/>
        </svg>
      </div>

      <!-- Error -->
      <div v-else-if="error" class="rounded-xl bg-red-50 border border-red-200 px-4 py-3 text-sm text-red-700">
        {{ error }}
      </div>

      <!-- Empty -->
      <div v-else-if="appointments.length === 0" class="text-center py-16 text-slate-500 text-sm">
        No appointments found.
      </div>

      <!-- List -->
      <ul v-else class="space-y-3">
        <li
          v-for="appt in appointments"
          :key="appt.id"
          class="bg-white border border-slate-200 rounded-2xl overflow-hidden"
        >
          <!-- Summary row (always visible) -->
          <button
            type="button"
            class="w-full text-left px-4 py-4 flex items-start justify-between gap-3 cursor-pointer hover:bg-slate-50 transition-colors duration-150"
            @click="toggle(appt.id)"
          >
            <div class="min-w-0">
              <p class="font-semibold text-sm text-text">
                {{ formatDate(appt.start_time) }}
                <span v-if="formatTime(appt.start_time)" class="font-normal text-slate-500">
                  · {{ formatTime(appt.start_time) }}
                </span>
                <span v-else-if="appt.session" class="font-normal text-slate-500 capitalize">
                  · {{ appt.session }} session
                </span>
              </p>
              <p class="text-xs text-slate-400 mt-0.5">
                {{ appt.doctor_id ? 'Assigned doctor' : 'Any available doctor' }}
              </p>
            </div>
            <div class="flex items-center gap-2 shrink-0">
              <span
                v-if="paymentByAppt(appt)"
                class="text-xs font-medium px-2.5 py-1 rounded-full"
                :class="PAYMENT_BADGE[paymentByAppt(appt).status]?.cls ?? 'bg-slate-100 text-slate-500'"
              >
                {{ PAYMENT_BADGE[paymentByAppt(appt).status]?.label ?? 'Payment' }}
              </span>
              <span
                class="text-xs font-medium px-2.5 py-1 rounded-full"
                :class="STATUS_CLASS[appt.status] ?? 'bg-slate-100 text-slate-500'"
              >
                {{ STATUS_LABEL[appt.status] ?? appt.status }}
              </span>
              <!-- Chevron -->
              <svg
                class="w-4 h-4 text-slate-400 transition-transform duration-200"
                :class="expandedId === appt.id ? 'rotate-180' : ''"
                viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"
              >
                <path stroke-linecap="round" stroke-linejoin="round" d="m19 9-7 7-7-7" />
              </svg>
            </div>
          </button>

          <!-- Expanded detail -->
          <div v-if="expandedId === appt.id" class="border-t border-slate-100 px-4 py-4 space-y-4">

            <!-- Consultation notes -->
            <div v-if="appt.notes">
              <p class="text-xs font-semibold text-slate-500 uppercase tracking-wide mb-1">Consultation Notes</p>
              <p class="text-sm text-text whitespace-pre-wrap">{{ appt.notes }}</p>
            </div>

            <!-- Diagnosis -->
            <template v-if="historyByAppt(appt).length">
              <div>
                <p class="text-xs font-semibold text-slate-500 uppercase tracking-wide mb-2">Diagnosis</p>
                <ul class="space-y-2">
                  <li
                    v-for="h in historyByAppt(appt)"
                    :key="h.id"
                    class="rounded-xl bg-slate-50 px-3 py-2.5"
                  >
                    <p class="text-sm font-medium text-text">{{ h.diagnosis }}</p>
                    <p v-if="h.notes" class="text-xs text-slate-500 mt-0.5">{{ h.notes }}</p>
                    <p v-if="h.diagnosed_at" class="text-xs text-slate-400 mt-1">
                      {{ formatDateShort(h.diagnosed_at) }}
                    </p>
                  </li>
                </ul>
              </div>
            </template>

            <!-- MC & Prescriptions from memos -->
            <template v-if="memosByAppt(appt).length">
              <div>
                <p class="text-xs font-semibold text-slate-500 uppercase tracking-wide mb-2">Documents Issued</p>
                <ul class="space-y-2">
                  <li
                    v-for="m in memosByAppt(appt)"
                    :key="m.id"
                    class="rounded-xl px-3 py-2.5"
                    :class="m.record_type === 'mc' ? 'bg-blue-50' : 'bg-amber-50'"
                  >
                    <div class="flex items-center gap-1.5 mb-0.5">
                      <span
                        class="text-xs font-semibold uppercase tracking-wide"
                        :class="m.record_type === 'mc' ? 'text-blue-600' : 'text-amber-700'"
                      >
                        {{ m.record_type === 'mc' ? 'Medical Certificate' : 'Prescription' }}
                      </span>
                    </div>
                    <p class="text-sm text-text">{{ m.content }}</p>
                    <p class="text-xs text-slate-400 mt-1">{{ formatDateShort(m.created_at) }}</p>
                  </li>
                </ul>
              </div>
            </template>

            <!-- Payment -->
            <template v-if="paymentByAppt(appt)">
              <div>
                <p class="text-xs font-semibold text-slate-500 uppercase tracking-wide mb-2">Payment</p>
                <div class="rounded-xl px-3 py-2.5 flex items-center justify-between gap-3"
                  :class="{
                    'bg-green-50': paymentByAppt(appt).status === 'paid',
                    'bg-amber-50': paymentByAppt(appt).status === 'pending',
                    'bg-red-50':   paymentByAppt(appt).status === 'failed',
                  }"
                >
                  <span class="text-sm font-medium capitalize"
                    :class="{
                      'text-green-700': paymentByAppt(appt).status === 'paid',
                      'text-amber-700': paymentByAppt(appt).status === 'pending',
                      'text-red-700':   paymentByAppt(appt).status === 'failed',
                    }"
                  >
                    {{ paymentByAppt(appt).status === 'paid' ? 'Paid' : paymentByAppt(appt).status === 'pending' ? 'Payment Pending' : 'Payment Failed' }}
                    <span v-if="paymentByAppt(appt).amount_cents" class="ml-1 text-slate-500 font-normal">· {{ formatCents(paymentByAppt(appt).amount_cents, paymentByAppt(appt).currency) }}</span>
                  </span>
                  <button
                    v-if="paymentByAppt(appt).status !== 'paid'"
                    type="button"
                    class="text-xs font-semibold text-primary hover:underline shrink-0 disabled:opacity-50"
                    :disabled="refreshingPayment === appt.id"
                    @click="payNow(appt)"
                  >
                    {{ refreshingPayment === appt.id ? 'Loading…' : 'Pay Now →' }}
                  </button>
                </div>
              </div>
            </template>

            <!-- Nothing to show for non-completed -->
            <div
              v-if="appt.status !== 'completed' && !appt.notes && !historyByAppt(appt).length && !memosByAppt(appt).length"
              class="text-sm text-slate-400 text-center py-2"
            >
              No details available yet.
            </div>

            <!-- Cancel button -->
            <div v-if="['scheduled', 'checked_in'].includes(appt.status)" class="pt-1">
              <button
                type="button"
                class="w-full text-sm font-medium text-red-600 hover:text-red-700 border border-red-200 hover:border-red-300 rounded-xl py-2 transition-colors duration-150 disabled:opacity-50"
                :disabled="cancellingId === appt.id"
                @click="cancelTarget = appt"
              >
                {{ cancellingId === appt.id ? 'Cancelling…' : 'Cancel Appointment' }}
              </button>
            </div>

          </div>
        </li>
      </ul>

    </main>
  </div>

  <!-- ─── Modal: Cancel Appointment ─────────────────────────────────────────── -->
  <Teleport to="body">
    <Transition name="modal">
      <div
        v-if="cancelTarget"
        class="fixed inset-0 z-50 flex items-end sm:items-center justify-center p-4"
        role="dialog"
        aria-modal="true"
        aria-labelledby="cancel-hist-title"
        @click.self="cancelTarget = null"
      >
        <div class="absolute inset-0 bg-black/40" aria-hidden="true" />
        <div class="relative w-full max-w-sm bg-white rounded-2xl shadow-xl p-6 space-y-5">
          <div class="w-12 h-12 rounded-2xl bg-red-50 flex items-center justify-center">
            <svg class="w-6 h-6 text-red-500" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.75" aria-hidden="true">
              <path stroke-linecap="round" stroke-linejoin="round" d="M6 18 18 6M6 6l12 12" />
            </svg>
          </div>
          <div>
            <h2 id="cancel-hist-title" class="font-heading font-semibold text-text text-lg">Cancel appointment?</h2>
            <p class="text-sm text-slate-500 mt-1 text-pretty">
              This will remove you from the queue. You'll need to book a new appointment to be seen.
            </p>
          </div>
          <div class="flex gap-3">
            <button
              type="button"
              class="flex-1 h-11 rounded-xl border border-slate-200 text-sm font-semibold text-slate-700 hover:bg-slate-50 transition-colors duration-150 cursor-pointer"
              @click="cancelTarget = null"
            >
              Keep Appointment
            </button>
            <button
              type="button"
              class="flex-1 h-11 rounded-xl bg-red-500 text-white text-sm font-semibold hover:bg-red-600 transition-colors duration-150 cursor-pointer disabled:opacity-50"
              :disabled="cancellingId === cancelTarget?.id"
              @click="confirmCancelAppointment"
            >
              {{ cancellingId === cancelTarget?.id ? 'Cancelling…' : 'Yes, Cancel' }}
            </button>
          </div>
        </div>
      </div>
    </Transition>
  </Teleport>
</template>
