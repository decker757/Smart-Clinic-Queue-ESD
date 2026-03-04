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

  const isAuthenticated = computed(() => !!jwt.value)

  function setAuth(token, userData) {
    jwt.value = token
    user.value = userData
  }

  function clearAuth() {
    jwt.value = null
    user.value = null
  }

  return { jwt, user, isAuthenticated, setAuth, clearAuth }
})
