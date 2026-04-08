<script setup>
import { ref, computed } from 'vue'
import { useAuthStore } from '@/stores/auth'

const emit = defineEmits(['complete'])

const API_BASE = import.meta.env.VITE_API_BASE_URL ?? ''
const authStore = useAuthStore()

const step = ref(1)
const submitting = ref(false)
const error = ref('')

const form = ref({
  phone: '',
  dob: '',
  gender: '',
  nric: '',
  allergies: '',
})

const allergyList = computed(() =>
  form.value.allergies
    .split(',')
    .map((a) => a.trim())
    .filter(Boolean)
)

// Step 1: phone + DOB + gender
// Step 2: NRIC + allergies

const step1Valid = computed(() =>
  form.value.phone.trim() && form.value.dob && form.value.gender
)

async function submit() {
  error.value = ''
  submitting.value = true
  try {
    const res = await fetch(`${API_BASE}/api/patients`, {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${authStore.jwt}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        phone: form.value.phone.trim(),
        dob: form.value.dob,
        gender: form.value.gender,
        nric: form.value.nric.trim() || null,
        allergies: allergyList.value,
      }),
    })
    if (!res.ok) {
      const body = await res.json().catch(() => ({}))
      throw new Error(body.detail ?? body.error ?? 'Failed to save profile')
    }
    emit('complete')
  } catch (e) {
    error.value = e.message
  } finally {
    submitting.value = false
  }
}
</script>

<template>
  <!-- Full-screen backdrop — pointer-events-none on nothing, intentionally blocks interaction -->
  <div class="fixed inset-0 z-50 flex items-center justify-center bg-black/50 backdrop-blur-sm px-4">
    <div class="w-full max-w-md bg-white rounded-2xl shadow-2xl overflow-hidden">

      <!-- Header -->
      <div class="px-6 pt-6 pb-4 border-b border-slate-100">
        <div class="w-10 h-10 rounded-xl bg-primary/10 flex items-center justify-center mb-3">
          <svg class="w-5 h-5 text-primary" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.75" aria-hidden="true">
            <path stroke-linecap="round" stroke-linejoin="round" d="M15.75 6a3.75 3.75 0 1 1-7.5 0 3.75 3.75 0 0 1 7.5 0ZM4.501 20.118a7.5 7.5 0 0 1 14.998 0A17.933 17.933 0 0 1 12 21.75c-2.676 0-5.216-.584-7.499-1.632Z" />
          </svg>
        </div>
        <h2 class="font-heading font-semibold text-text text-lg">Complete your profile</h2>
        <p class="text-slate-500 text-sm mt-0.5">We need a few details before you can use SmartClinic.</p>

        <!-- Step indicator -->
        <div class="flex gap-1.5 mt-4">
          <div class="h-1 flex-1 rounded-full transition-colors duration-300"
            :class="step >= 1 ? 'bg-primary' : 'bg-slate-100'" />
          <div class="h-1 flex-1 rounded-full transition-colors duration-300"
            :class="step >= 2 ? 'bg-primary' : 'bg-slate-100'" />
        </div>
      </div>

      <!-- Step 1: Personal details -->
      <div v-if="step === 1" class="px-6 py-5 space-y-4">
        <!-- Name (read-only from BetterAuth) -->
        <div>
          <label class="block text-xs font-medium text-slate-600 mb-1">Full name</label>
          <div class="w-full px-3 py-2 text-sm bg-slate-50 border border-slate-200 rounded-xl text-slate-500">
            {{ authStore.user?.name ?? '—' }}
          </div>
        </div>

        <!-- Phone -->
        <div>
          <label class="block text-xs font-medium text-slate-600 mb-1" for="ob-phone">
            Mobile number <span class="text-red-500">*</span>
          </label>
          <input
            id="ob-phone"
            v-model="form.phone"
            type="tel"
            placeholder="+65 9123 4567"
            class="w-full px-3 py-2 text-sm border border-slate-200 rounded-xl focus:outline-none focus:ring-2 focus:ring-primary/30 focus:border-primary transition-colors"
          />
          <p class="text-xs text-slate-400 mt-1">Used to send queue notifications via SMS.</p>
        </div>

        <!-- DOB -->
        <div>
          <label class="block text-xs font-medium text-slate-600 mb-1" for="ob-dob">
            Date of birth <span class="text-red-500">*</span>
          </label>
          <input
            id="ob-dob"
            v-model="form.dob"
            type="date"
            :max="new Date().toISOString().split('T')[0]"
            class="w-full px-3 py-2 text-sm border border-slate-200 rounded-xl focus:outline-none focus:ring-2 focus:ring-primary/30 focus:border-primary transition-colors"
          />
        </div>

        <!-- Gender -->
        <div>
          <label class="block text-xs font-medium text-slate-600 mb-2">
            Gender <span class="text-red-500">*</span>
          </label>
          <div class="flex gap-2">
            <button
              v-for="opt in ['Male', 'Female', 'Prefer not to say']"
              :key="opt"
              type="button"
              class="flex-1 py-2 text-xs font-medium rounded-xl border transition-colors duration-150 cursor-pointer"
              :class="form.gender === opt
                ? 'bg-primary text-white border-primary'
                : 'bg-white text-slate-600 border-slate-200 hover:border-primary hover:text-primary'"
              @click="form.gender = opt"
            >
              {{ opt }}
            </button>
          </div>
        </div>

        <button
          type="button"
          class="w-full h-11 rounded-xl bg-cta text-white font-semibold text-sm disabled:opacity-50 hover:bg-cta/90 transition-colors duration-150 cursor-pointer mt-2"
          :disabled="!step1Valid"
          @click="step = 2"
        >
          Continue
        </button>
      </div>

      <!-- Step 2: Medical details -->
      <div v-else class="px-6 py-5 space-y-4">
        <!-- NRIC -->
        <div>
          <label class="block text-xs font-medium text-slate-600 mb-1" for="ob-nric">
            NRIC / FIN
          </label>
          <input
            id="ob-nric"
            v-model="form.nric"
            type="text"
            placeholder="S1234567A"
            maxlength="9"
            class="w-full px-3 py-2 text-sm border border-slate-200 rounded-xl focus:outline-none focus:ring-2 focus:ring-primary/30 focus:border-primary transition-colors uppercase"
          />
          <p class="text-xs text-slate-400 mt-1">Optional — helps verify your identity at the clinic.</p>
        </div>

        <!-- Allergies -->
        <div>
          <label class="block text-xs font-medium text-slate-600 mb-1" for="ob-allergies">
            Known allergies
          </label>
          <input
            id="ob-allergies"
            v-model="form.allergies"
            type="text"
            placeholder="e.g. penicillin, peanuts, latex"
            class="w-full px-3 py-2 text-sm border border-slate-200 rounded-xl focus:outline-none focus:ring-2 focus:ring-primary/30 focus:border-primary transition-colors"
          />
          <p class="text-xs text-slate-400 mt-1">Separate multiple allergies with commas. Leave blank if none.</p>
          <!-- Allergy tags preview -->
          <div v-if="allergyList.length" class="flex flex-wrap gap-1.5 mt-2">
            <span
              v-for="a in allergyList"
              :key="a"
              class="px-2 py-0.5 bg-amber-50 text-amber-700 border border-amber-200 text-xs rounded-full"
            >
              {{ a }}
            </span>
          </div>
        </div>

        <!-- Error -->
        <div v-if="error" role="alert" class="px-3 py-2 bg-red-50 border border-red-200 rounded-xl text-xs text-red-700">
          {{ error }}
        </div>

        <div class="flex gap-2 mt-2">
          <button
            type="button"
            class="px-4 h-11 rounded-xl border border-slate-200 text-sm text-slate-500 hover:text-text transition-colors duration-150 cursor-pointer"
            :disabled="submitting"
            @click="step = 1"
          >
            Back
          </button>
          <button
            type="button"
            class="flex-1 h-11 rounded-xl bg-cta text-white font-semibold text-sm disabled:opacity-50 hover:bg-cta/90 transition-colors duration-150 cursor-pointer"
            :disabled="submitting"
            @click="submit"
          >
            {{ submitting ? 'Saving…' : 'Done' }}
          </button>
        </div>
      </div>

    </div>
  </div>
</template>
