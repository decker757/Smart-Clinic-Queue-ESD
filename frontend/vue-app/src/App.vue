<script setup>
import { ref, watch } from 'vue'
import { RouterView } from 'vue-router'
import { useAuthStore } from '@/stores/auth'
import OnboardingModal from '@/components/OnboardingModal.vue'

const API_BASE = import.meta.env.VITE_API_BASE_URL ?? ''
const authStore = useAuthStore()

const showOnboarding = ref(false)

async function checkProfile() {
  if (!authStore.isAuthenticated || !authStore.user?.id || authStore.isStaff) return
  try {
    const res = await fetch(`${API_BASE}/api/patients/${authStore.user.id}`, {
      headers: { Authorization: `Bearer ${authStore.jwt}` },
    })
    if (res.status === 404) showOnboarding.value = true
  } catch {
    // network error — don't block the user
  }
}

// Trigger check whenever the user logs in
watch(() => authStore.isAuthenticated, (authed) => {
  if (authed) checkProfile()
  else showOnboarding.value = false
})
</script>

<template>
  <RouterView />
  <OnboardingModal v-if="showOnboarding" @complete="showOnboarding = false" />
</template>
