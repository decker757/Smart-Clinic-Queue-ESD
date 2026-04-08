<script setup>
import { ref, onMounted } from 'vue'
import { useRouter } from 'vue-router'
import { useAuthStore } from '@/stores/auth'

const router = useRouter()
const authStore = useAuthStore()

import { API_BASE } from '@/utils/env'

const loading = ref(true)   // fetching existing profile
const saving = ref(false)
const error = ref('')

// Form fields
const phone = ref('')
const dob = ref('')
const nric = ref('')
const gender = ref('')
const allergiesInput = ref('')  // comma-separated string

let isNew = true  // true = POST, false = PUT

function authHeaders() {
  return { Authorization: `Bearer ${authStore.jwt}`, 'Content-Type': 'application/json' }
}

async function loadProfile() {
  const pid = authStore.user?.id
  try {
    const res = await fetch(`${API_BASE}/api/composite/patients/${pid}`, {
      headers: { Authorization: `Bearer ${authStore.jwt}` },
    })
    if (res.status === 404) { isNew = true; return }
    if (!res.ok) return
    const data = await res.json()
    // Has a real profile already
    if (data.phone) {
      isNew = false
      phone.value = data.phone
      dob.value = data.dob ? data.dob.slice(0, 10) : ''
      nric.value = data.nric
      gender.value = data.gender ?? ''
      allergiesInput.value = (data.allergies ?? []).join(', ')
    }
  } catch {
    // ignore, treat as new
  } finally {
    loading.value = false
  }
}

function normalizePhone(raw) {
  const digits = raw.replace(/\D/g, '')
  if (digits.startsWith('65')) return `+${digits}`
  return `+65${digits}`
}

async function save() {
  if (!phone.value.trim() || !dob.value || !nric.value.trim()) {
    error.value = 'Phone, date of birth and NRIC are required.'
    return
  }
  error.value = ''
  saving.value = true
  const pid = authStore.user?.id
  const normalizedPhone = normalizePhone(phone.value)
  const allergies = allergiesInput.value
    .split(',')
    .map(s => s.trim())
    .filter(Boolean)

  const body = isNew
    ? { phone: normalizedPhone, dob: dob.value, nric: nric.value.trim(), gender: gender.value || null, allergies }
    : { phone: normalizedPhone, allergies }

  try {
    const res = isNew
      ? await fetch(`${API_BASE}/api/composite/patients`, {
          method: 'POST',
          headers: authHeaders(),
          body: JSON.stringify(body),
        })
      : await fetch(`${API_BASE}/api/composite/patients/${pid}`, {
          method: 'PUT',
          headers: authHeaders(),
          body: JSON.stringify(body),
        })

    if (!res.ok) {
      const data = await res.json().catch(() => ({}))
      throw new Error(data.detail ?? data.error ?? 'Failed to save profile')
    }
    router.push('/dashboard')
  } catch (e) {
    error.value = e.message
  } finally {
    saving.value = false
  }
}

onMounted(() => {
  if (!authStore.user?.id) { router.push('/login'); return }
  loadProfile()
})
</script>

<template>
  <div class="min-h-dvh bg-surface flex items-center justify-center px-4 py-10">
    <div class="w-full max-w-md bg-white rounded-2xl border border-slate-200 shadow-sm p-6 space-y-6">

      <div>
        <h1 class="font-heading font-semibold text-xl text-text">Complete your profile</h1>
        <p class="text-sm text-slate-500 mt-1">We need a few details before you can book appointments.</p>
      </div>

      <div v-if="loading" class="flex justify-center py-8">
        <svg class="w-6 h-6 animate-spin text-primary" viewBox="0 0 24 24" fill="none">
          <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"/>
          <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8v8H4z"/>
        </svg>
      </div>

      <form v-else class="space-y-4" @submit.prevent="save">

        <div v-if="error" class="px-4 py-3 bg-red-50 border border-red-200 rounded-xl text-sm text-red-700">
          {{ error }}
        </div>

        <!-- Phone -->
        <div>
          <label class="block text-xs font-medium text-slate-600 mb-1" for="phone">
            Phone number <span class="text-red-500">*</span>
          </label>
          <input
            id="phone"
            v-model="phone"
            type="tel"
            placeholder="+65 9123 4567"
            class="w-full px-3 py-2 text-sm border border-slate-200 rounded-xl focus:outline-none focus:ring-2 focus:ring-primary/30 focus:border-primary transition-colors"
          />
        </div>

        <!-- DOB -->
        <div>
          <label class="block text-xs font-medium text-slate-600 mb-1" for="dob">
            Date of birth <span class="text-red-500">*</span>
          </label>
          <input
            id="dob"
            v-model="dob"
            type="date"
            :disabled="!isNew"
            class="w-full px-3 py-2 text-sm border border-slate-200 rounded-xl transition-colors"
            :class="!isNew ? 'bg-slate-50 text-slate-400 cursor-not-allowed' : 'focus:outline-none focus:ring-2 focus:ring-primary/30 focus:border-primary'"
          />
        </div>

        <!-- NRIC -->
        <div>
          <label class="block text-xs font-medium text-slate-600 mb-1" for="nric">
            NRIC / FIN <span class="text-red-500">*</span>
          </label>
          <input
            id="nric"
            v-model="nric"
            type="text"
            placeholder="S1234567A"
            :disabled="!isNew"
            class="w-full px-3 py-2 text-sm border border-slate-200 rounded-xl transition-colors"
            :class="!isNew ? 'bg-slate-50 text-slate-400 cursor-not-allowed' : 'focus:outline-none focus:ring-2 focus:ring-primary/30 focus:border-primary'"
          />
        </div>

        <!-- Gender -->
        <div>
          <label class="block text-xs font-medium text-slate-600 mb-1" for="gender">Gender</label>
          <select
            id="gender"
            v-model="gender"
            :disabled="!isNew"
            class="w-full px-3 py-2 text-sm border border-slate-200 rounded-xl transition-colors bg-white"
            :class="!isNew ? 'bg-slate-50 text-slate-400 cursor-not-allowed' : 'focus:outline-none focus:ring-2 focus:ring-primary/30 focus:border-primary'"
          >
            <option value="">Prefer not to say</option>
            <option value="male">Male</option>
            <option value="female">Female</option>
            <option value="other">Other</option>
          </select>
        </div>

        <!-- Allergies -->
        <div>
          <label class="block text-xs font-medium text-slate-600 mb-1" for="allergies">
            Allergies <span class="text-slate-400 font-normal">(comma-separated, optional)</span>
          </label>
          <input
            id="allergies"
            v-model="allergiesInput"
            type="text"
            placeholder="e.g. Penicillin, Peanuts"
            class="w-full px-3 py-2 text-sm border border-slate-200 rounded-xl focus:outline-none focus:ring-2 focus:ring-primary/30 focus:border-primary transition-colors"
          />
        </div>

        <button
          type="submit"
          class="w-full py-2.5 bg-cta text-white text-sm font-semibold rounded-xl hover:bg-cta/90 disabled:opacity-50 transition-colors duration-150 cursor-pointer"
          :disabled="saving"
        >
          {{ saving ? 'Saving…' : (isNew ? 'Save & Continue' : 'Update Profile') }}
        </button>

        <button
          v-if="!isNew"
          type="button"
          class="w-full py-2 text-sm text-slate-500 hover:text-text transition-colors duration-150 cursor-pointer"
          @click="router.push('/dashboard')"
        >
          Cancel
        </button>

      </form>
    </div>
  </div>
</template>
