<script setup>
import { ref, computed, onMounted, onUnmounted } from 'vue'
import { useAuthStore } from '@/stores/auth'
import { useAuth } from '@/composables/useAuth'
import { useDoctor } from '@/composables/useDoctor'
import { formatGender, formatDOB } from '@/utils/formatters'
import AppButton from '@/components/ui/AppButton.vue'
import AppAlert from '@/components/ui/AppAlert.vue'

const authStore = useAuthStore()
const { signOut } = useAuth()
const {
  fetchDoctorInfo,
  fetchDoctorSlots,
  callNextPatient,
  completeConsultation,
  fetchPatient,
  fetchPatientHistory,
} = useDoctor()

// ─── State ───────────────────────────────────────────────────────────────────
const loading = ref(true)
const error = ref('')
const actionError = ref('')
const actionSuccess = ref('')
const callLoading = ref(false)
const completeLoading = ref(false)
const patientLoading = ref(false)

const doctor = ref(null)
const slots = ref([])
const currentPatient = ref(null)
const patientProfile = ref(null)
const patientHistory = ref([])
const showPatientModal = ref(false)

// ─── Consultation form ────────────────────────────────────────────────────────
const showConsultationModal = ref(false)
const consultationDone = ref(false)
const paymentLink = ref(null)
const consultForm = ref({
  diagnosis: '',
  consultationNotes: '',
  prescribedMedication: '',
  issueMc: false,
  mcDays: '',
  mcStartDate: '',
  mcReason: '',
})

let pollTimer = null
const POLL_MS = 30_000

// ─── Computed ─────────────────────────────────────────────────────────────────
const greeting = computed(() => {
  const h = new Date().getHours()
  if (h < 12) return 'Good morning'
  if (h < 18) return 'Good afternoon'
  return 'Good evening'
})

const firstName = computed(() => authStore.user?.name?.split(' ')[0] ?? 'Doctor')

const todaySlots = computed(() => {
  const today = new Date().toDateString()
  return slots.value.filter((s) => {
    if (!s.start_time) return true
    return new Date(s.start_time).toDateString() === today
  })
})

const SLOT_STATUS_BADGE = {
  available: { label: 'Available', classes: 'bg-emerald-100 text-emerald-700' },
  booked:    { label: 'Booked',    classes: 'bg-amber-100 text-amber-700' },
  completed: { label: 'Completed', classes: 'bg-slate-100 text-slate-500' },
  cancelled: { label: 'Cancelled', classes: 'bg-red-100 text-red-600' },
}

function slotStatusBadge(status) {
  return SLOT_STATUS_BADGE[status] ?? { label: status, classes: 'bg-slate-100 text-slate-500' }
}

// ─── Data loading ─────────────────────────────────────────────────────────────
async function loadSlots() {
  const doctorId = authStore.user?.id
  if (!doctorId) return
  const slotsData = await fetchDoctorSlots(doctorId)
  slots.value = slotsData ?? []
}

async function loadDashboard() {
  try {
    const doctorId = authStore.user?.id
    if (!doctorId) return

    const [doctorData, slotsData] = await Promise.all([
      fetchDoctorInfo(doctorId),
      fetchDoctorSlots(doctorId),
    ])

    doctor.value = doctorData
    slots.value = slotsData ?? []
    error.value = ''
  } catch {
    error.value = 'Could not load dashboard. Please refresh.'
  } finally {
    loading.value = false
  }
}

// ─── Actions ──────────────────────────────────────────────────────────────────
async function handleCallNext() {
  actionError.value = ''
  actionSuccess.value = ''
  callLoading.value = true
  try {
    const session = new Date().getHours() < 12 ? 'morning' : 'afternoon'
    const result = await callNextPatient(session, authStore.user?.id)
    currentPatient.value = result
    actionSuccess.value = `Patient #${result.queue_number} called!`
    setTimeout(() => { actionSuccess.value = '' }, 3000)
  } catch (e) {
    actionError.value = e.message ?? 'No checked-in patients in queue'
  } finally {
    callLoading.value = false
  }
}

function openConsultationModal() {
  consultForm.value = { diagnosis: '', consultationNotes: '', prescribedMedication: '', issueMc: false, mcDays: '', mcStartDate: '', mcReason: '' }
  paymentLink.value = null
  consultationDone.value = false
  actionError.value = ''
  showConsultationModal.value = true
}

async function handleComplete() {
  if (!currentPatient.value?.appointment_id) return
  actionError.value = ''
  actionSuccess.value = ''
  completeLoading.value = true
  try {
    const f = consultForm.value
    const result = await completeConsultation({
      appointmentId: currentPatient.value.appointment_id,
      patientId: currentPatient.value.patient_id,
      doctorId: authStore.user?.id,
      diagnosis: f.diagnosis,
      consultationNotes: f.consultationNotes,
      prescribedMedication: f.prescribedMedication,
      mcDays: f.issueMc && f.mcDays ? parseInt(f.mcDays, 10) : null,
      mcStartDate: f.issueMc ? f.mcStartDate : null,
      mcReason: f.issueMc ? f.mcReason : null,
    })
    paymentLink.value = result.payment_link ?? null
    consultationDone.value = true
    actionSuccess.value = 'Consultation completed!'
    currentPatient.value = null
    patientProfile.value = null
    setTimeout(() => { actionSuccess.value = '' }, 4000)
  } catch (e) {
    actionError.value = e.message ?? 'Failed to complete consultation'
  } finally {
    completeLoading.value = false
  }
}

async function handleViewPatient() {
  if (!currentPatient.value?.patient_id) return
  showPatientModal.value = true
  patientLoading.value = true
  patientProfile.value = null
  patientHistory.value = []
  try {
    const [profile, history] = await Promise.all([
      fetchPatient(currentPatient.value.patient_id),
      fetchPatientHistory(currentPatient.value.patient_id),
    ])
    patientProfile.value = profile
    patientHistory.value = history ?? []
  } catch {
    actionError.value = 'Failed to load patient details'
    showPatientModal.value = false
  } finally {
    patientLoading.value = false
  }
}

onMounted(() => {
  loadDashboard()
  pollTimer = setInterval(loadSlots, POLL_MS)
})

onUnmounted(() => {
  clearInterval(pollTimer)
})
</script>

<template>
  <div class="min-h-dvh bg-surface">

    <!-- ─── Header ───────────────────────────────────────────────────────── -->
    <header class="sticky top-0 z-20 bg-white border-b border-slate-200">
      <div class="max-w-3xl mx-auto px-4 h-14 flex items-center justify-between">
        <div class="flex items-center gap-2">
          <svg class="w-6 h-6 text-primary" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true">
            <path fill-rule="evenodd"
              d="M12 2.25a.75.75 0 0 1 .75.75v8.25H21a.75.75 0 0 1 0 1.5h-8.25V21a.75.75 0 0 1-1.5 0v-8.25H3a.75.75 0 0 1 0-1.5h8.25V3a.75.75 0 0 1 .75-.75Z"
              clip-rule="evenodd" />
          </svg>
          <span class="font-heading font-semibold text-text text-sm tracking-tight">SmartClinic</span>
          <span class="text-xs font-medium px-2 py-0.5 rounded-full bg-primary/10 text-primary ml-1">
            Doctor
          </span>
        </div>
        <div class="flex items-center gap-3">
          <span class="text-sm text-slate-500 hidden sm:inline">Dr. {{ authStore.user?.name }}</span>
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
    <main class="max-w-3xl mx-auto px-4 py-8 space-y-8">

      <!-- Greeting -->
      <div>
        <p class="text-sm text-slate-500 font-body">{{ greeting }},</p>
        <h1 class="font-heading font-semibold text-2xl text-text">Dr. {{ firstName }}</h1>
        <p v-if="doctor" class="text-sm text-slate-400 mt-0.5">{{ doctor.specialisation }}</p>
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

      <!-- ─── Current Patient ─────────────────────────────────────────── -->
      <section aria-labelledby="current-patient-heading">
        <h2 id="current-patient-heading" class="text-xs font-semibold uppercase tracking-widest text-slate-400 mb-3">
          Current Patient
        </h2>

        <!-- Loading skeleton -->
        <div v-if="loading" class="bg-white rounded-2xl border border-slate-200 p-5 space-y-3 animate-pulse" aria-busy="true">
          <div class="h-5 w-40 bg-slate-100 rounded" />
          <div class="h-4 w-28 bg-slate-100 rounded" />
          <div class="h-11 w-full bg-slate-100 rounded-xl mt-2" />
        </div>

        <!-- No current patient empty state -->
        <div
          v-else-if="!currentPatient"
          class="bg-white rounded-2xl border border-slate-200 p-8 text-center"
        >
          <div class="w-14 h-14 rounded-2xl bg-primary/8 flex items-center justify-center mx-auto mb-4">
            <svg class="w-7 h-7 text-primary" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.75" aria-hidden="true">
              <path stroke-linecap="round" stroke-linejoin="round"
                d="M15.75 6a3.75 3.75 0 1 1-7.5 0 3.75 3.75 0 0 1 7.5 0ZM4.501 20.118a7.5 7.5 0 0 1 14.998 0A17.933 17.933 0 0 1 12 21.75c-2.676 0-5.216-.584-7.499-1.632Z" />
            </svg>
          </div>
          <p class="font-heading font-semibold text-text text-base">No patient called yet</p>
          <p class="text-slate-500 text-sm mt-1 text-pretty">Call the next patient to begin consultation.</p>
          <div class="mt-5 max-w-xs mx-auto">
            <AppButton :loading="callLoading" @click="handleCallNext">
              Call Next Patient
            </AppButton>
          </div>
        </div>

        <!-- Current patient card -->
        <div v-else class="bg-white rounded-2xl border border-slate-200 overflow-hidden">
          <div class="border-l-4 border-primary px-5 pt-5 pb-4">
            <div class="flex items-start justify-between gap-3">
              <div>
                <p class="font-heading font-semibold text-text text-lg leading-snug">
                  Patient #{{ currentPatient.queue_number }}
                </p>
                <p class="text-sm text-slate-500 mt-0.5">
                  Session: {{ currentPatient.session }}
                </p>
              </div>
              <span class="shrink-0 text-xs font-semibold px-2.5 py-1 rounded-full bg-primary/10 text-primary">
                In Consultation
              </span>
            </div>
          </div>
          <div class="px-5 pb-5 pt-4 space-y-3">
            <AppButton variant="secondary" @click="handleViewPatient">
              View Patient Profile &amp; History
            </AppButton>
            <AppButton @click="openConsultationModal">
              Complete Consultation
            </AppButton>
            <AppButton variant="secondary" :loading="callLoading" :disabled="!!currentPatient" @click="handleCallNext">
              Call Next Patient
            </AppButton>
          </div>
        </div>
      </section>

      <!-- ─── Today's Schedule ───────────────────────────────────────── -->
      <section aria-labelledby="slots-heading">
        <h2 id="slots-heading" class="text-xs font-semibold uppercase tracking-widest text-slate-400 mb-3">
          Today's Schedule
        </h2>

        <!-- Loading skeleton -->
        <div v-if="loading" class="space-y-3">
          <div v-for="i in 3" :key="i" class="bg-white rounded-2xl border border-slate-200 p-4 animate-pulse">
            <div class="flex justify-between">
              <div class="h-4 w-24 bg-slate-100 rounded" />
              <div class="h-4 w-16 bg-slate-100 rounded-full" />
            </div>
          </div>
        </div>

        <!-- No slots -->
        <div
          v-else-if="todaySlots.length === 0"
          class="bg-white rounded-2xl border border-slate-200 p-8 text-center"
        >
          <p class="font-heading font-semibold text-text text-base">No slots today</p>
          <p class="text-slate-500 text-sm mt-1">Your schedule is clear for today.</p>
        </div>

        <!-- Slots list -->
        <div v-else class="space-y-3">
          <div
            v-for="slot in todaySlots"
            :key="slot.id"
            class="bg-white rounded-2xl border border-slate-200 px-5 py-4 flex items-center justify-between gap-3"
          >
            <p class="font-semibold text-sm text-text">
              {{ slot.start_time
                ? new Date(slot.start_time).toLocaleTimeString('en-SG', { hour: '2-digit', minute: '2-digit' })
                : '—' }}
              <span class="text-slate-400 font-normal mx-1">—</span>
              {{ slot.end_time
                ? new Date(slot.end_time).toLocaleTimeString('en-SG', { hour: '2-digit', minute: '2-digit' })
                : '—' }}
            </p>
            <span
              class="shrink-0 text-xs font-semibold px-2.5 py-1 rounded-full"
              :class="slotStatusBadge(slot.status).classes"
            >
              {{ slotStatusBadge(slot.status).label }}
            </span>
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
      <div class="bg-white rounded-2xl w-full max-w-lg max-h-[85vh] overflow-y-auto shadow-xl">

        <!-- Modal header -->
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

        <!-- Modal body -->
        <div class="p-5 space-y-5">

          <!-- Loading -->
          <div v-if="patientLoading" class="space-y-3 animate-pulse">
            <div class="h-5 w-32 bg-slate-100 rounded" />
            <div class="h-4 w-48 bg-slate-100 rounded" />
            <div class="h-4 w-40 bg-slate-100 rounded" />
          </div>

          <!-- Profile -->
          <div v-else-if="patientProfile">
            <div class="flex items-center gap-3 mb-4">
              <div class="w-12 h-12 rounded-full bg-primary/10 flex items-center justify-center shrink-0">
                <svg class="w-6 h-6 text-primary" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.75" aria-hidden="true">
                  <path stroke-linecap="round" stroke-linejoin="round"
                    d="M15.75 6a3.75 3.75 0 1 1-7.5 0 3.75 3.75 0 0 1 7.5 0ZM4.501 20.118a7.5 7.5 0 0 1 14.998 0A17.933 17.933 0 0 1 12 21.75c-2.676 0-5.216-.584-7.499-1.632Z" />
                </svg>
              </div>
              <div>
                <p class="font-heading font-semibold text-text">{{ patientProfile.nric }}</p>
                <p class="text-sm text-slate-500">
                  {{ formatGender(patientProfile.gender) }} · DOB: {{ formatDOB(patientProfile.dob) }}
                </p>
              </div>
            </div>

            <!-- Allergies -->
            <div
              v-if="patientProfile.allergies?.length"
              class="bg-amber-50 border border-amber-200 rounded-xl px-4 py-3 mb-4"
            >
              <p class="text-xs font-semibold text-amber-700 uppercase tracking-wide mb-1.5">Allergies</p>
              <div class="flex flex-wrap gap-1.5">
                <span
                  v-for="allergy in patientProfile.allergies"
                  :key="allergy"
                  class="text-xs px-2 py-0.5 bg-amber-100 text-amber-800 rounded-full font-medium"
                >
                  {{ allergy }}
                </span>
              </div>
            </div>

            <!-- Medical history -->
            <h4 class="text-xs font-semibold uppercase tracking-widest text-slate-400 mb-3">
              Medical History
            </h4>

            <div v-if="patientHistory.length === 0" class="text-sm text-slate-400 text-center py-4">
              No medical history on record.
            </div>

            <div v-else class="space-y-3">
              <div
                v-for="entry in patientHistory"
                :key="entry.id"
                class="border border-slate-100 rounded-xl px-4 py-3"
              >
                <div class="flex items-start justify-between gap-2">
                  <p class="font-semibold text-sm text-text">{{ entry.diagnosis }}</p>
                  <span class="text-xs text-slate-400 shrink-0">
                    {{ entry.diagnosed_at
                      ? new Date(entry.diagnosed_at).toLocaleDateString('en-SG', { day: 'numeric', month: 'short', year: 'numeric' })
                      : '—' }}
                  </span>
                </div>
                <p v-if="entry.notes" class="text-xs text-slate-500 mt-1">{{ entry.notes }}</p>
              </div>
            </div>
          </div>

        </div>
      </div>
    </div>

    <!-- ─── Consultation Form Modal ───────────────────────────────────── -->
    <div
      v-if="showConsultationModal"
      class="fixed inset-0 z-50 flex items-end sm:items-center justify-center p-4 bg-black/40"
      @click.self="showConsultationModal = false"
    >
      <div class="bg-white rounded-2xl w-full max-w-lg max-h-[90vh] overflow-y-auto shadow-xl">

        <!-- Modal header -->
        <div class="sticky top-0 bg-white border-b border-slate-100 px-5 py-4 flex items-center justify-between">
          <h3 class="font-heading font-semibold text-text">Complete Consultation</h3>
          <button
            type="button"
            class="text-slate-400 hover:text-text transition-colors cursor-pointer"
            aria-label="Close"
            @click="showConsultationModal = false"
          >
            <svg class="w-5 h-5" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true">
              <path stroke-linecap="round" stroke-linejoin="round" d="M6 18 18 6M6 6l12 12" />
            </svg>
          </button>
        </div>

        <!-- Success / payment link state -->
        <div v-if="consultationDone" class="p-5 space-y-4">
          <div class="flex items-center gap-3 p-4 bg-emerald-50 border border-emerald-200 rounded-xl">
            <svg class="w-6 h-6 text-emerald-600 shrink-0" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true">
              <path stroke-linecap="round" stroke-linejoin="round" d="M9 12.75 11.25 15 15 9.75M21 12a9 9 0 1 1-18 0 9 9 0 0 1 18 0Z" />
            </svg>
            <p class="text-sm font-semibold text-emerald-700">Consultation completed successfully.</p>
          </div>
          <div v-if="paymentLink" class="p-4 bg-slate-50 border border-slate-200 rounded-xl">
            <p class="text-xs font-semibold text-slate-500 uppercase tracking-wide mb-2">Payment Link</p>
            <a
              :href="paymentLink"
              target="_blank"
              rel="noopener noreferrer"
              class="text-sm text-primary underline break-all"
            >{{ paymentLink }}</a>
          </div>
          <AppButton variant="secondary" @click="showConsultationModal = false">Close</AppButton>
        </div>

        <!-- Form -->
        <form v-else class="p-5 space-y-5" @submit.prevent="handleComplete">

          <AppAlert v-if="actionError" :message="actionError" />

          <!-- Diagnosis -->
          <div>
            <label class="block text-xs font-semibold text-slate-600 uppercase tracking-wide mb-1.5" for="diagnosis">
              Diagnosis
            </label>
            <input
              id="diagnosis"
              v-model="consultForm.diagnosis"
              type="text"
              placeholder="e.g. Acute upper respiratory infection"
              class="w-full rounded-xl border border-slate-200 px-3.5 py-2.5 text-sm focus:outline-none focus:ring-2 focus:ring-primary/30 focus:border-primary"
            />
          </div>

          <!-- Consultation notes -->
          <div>
            <label class="block text-xs font-semibold text-slate-600 uppercase tracking-wide mb-1.5" for="notes">
              Consultation Notes
            </label>
            <textarea
              id="notes"
              v-model="consultForm.consultationNotes"
              rows="3"
              placeholder="Clinical observations, treatment plan…"
              class="w-full rounded-xl border border-slate-200 px-3.5 py-2.5 text-sm resize-none focus:outline-none focus:ring-2 focus:ring-primary/30 focus:border-primary"
            />
          </div>

          <!-- Prescription -->
          <div>
            <label class="block text-xs font-semibold text-slate-600 uppercase tracking-wide mb-1.5" for="medication">
              Prescribed Medication
            </label>
            <textarea
              id="medication"
              v-model="consultForm.prescribedMedication"
              rows="2"
              placeholder="e.g. Paracetamol 500mg — 3x daily for 3 days"
              class="w-full rounded-xl border border-slate-200 px-3.5 py-2.5 text-sm resize-none focus:outline-none focus:ring-2 focus:ring-primary/30 focus:border-primary"
            />
          </div>

          <!-- MC toggle -->
          <div class="border border-slate-200 rounded-xl p-4 space-y-4">
            <label class="flex items-center gap-3 cursor-pointer select-none">
              <input
                v-model="consultForm.issueMc"
                type="checkbox"
                class="w-4 h-4 rounded accent-primary"
              />
              <span class="text-sm font-semibold text-text">Issue Medical Certificate (MC)</span>
            </label>

            <div v-if="consultForm.issueMc" class="space-y-3 pt-1">
              <div class="grid grid-cols-2 gap-3">
                <div>
                  <label class="block text-xs font-semibold text-slate-500 mb-1" for="mc-days">Days</label>
                  <input
                    id="mc-days"
                    v-model="consultForm.mcDays"
                    type="number"
                    min="1"
                    max="30"
                    placeholder="2"
                    class="w-full rounded-xl border border-slate-200 px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-primary/30 focus:border-primary"
                  />
                </div>
                <div>
                  <label class="block text-xs font-semibold text-slate-500 mb-1" for="mc-start">Start Date</label>
                  <input
                    id="mc-start"
                    v-model="consultForm.mcStartDate"
                    type="date"
                    class="w-full rounded-xl border border-slate-200 px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-primary/30 focus:border-primary"
                  />
                </div>
              </div>
              <div>
                <label class="block text-xs font-semibold text-slate-500 mb-1" for="mc-reason">Reason</label>
                <input
                  id="mc-reason"
                  v-model="consultForm.mcReason"
                  type="text"
                  placeholder="e.g. Fever and fatigue"
                  class="w-full rounded-xl border border-slate-200 px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-primary/30 focus:border-primary"
                />
              </div>
            </div>
          </div>

          <AppButton type="submit" :loading="completeLoading">
            Submit &amp; Complete
          </AppButton>
        </form>

      </div>
    </div>

  </div>
</template>
