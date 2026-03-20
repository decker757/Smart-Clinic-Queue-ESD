import { defineStore } from 'pinia'
import { ref, computed } from 'vue'

/**
 * Auth store — holds JWT and user in memory only.
 * Intentionally not persisted to localStorage to reduce XSS exposure.
 * On refresh, user must re-authenticate.
 */
export const useAuthStore = defineStore('auth', () => {
  const jwt = ref(null)
  const user = ref(null)
  const role = ref(null)

  const isAuthenticated = computed(() => !!jwt.value)
  const isDoctor = computed(() => role.value === 'doctor')
  const isStaff = computed(() => ['staff', 'doctor', 'admin'].includes(role.value))

  function setAuth(token, userData) {
    jwt.value = token
    user.value = userData
    // Decode role from JWT payload
    try {
      const payload = JSON.parse(atob(token.split('.')[1]))
      role.value = payload.role ?? null
    } catch {
      role.value = null
    }
  }

  function clearAuth() {
    jwt.value = null
    user.value = null
    role.value = null
  }

  return { jwt, user, role, isAuthenticated, isDoctor, isStaff, setAuth, clearAuth }
})
