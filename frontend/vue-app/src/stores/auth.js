import { defineStore } from 'pinia'
import { ref, computed } from 'vue'

/**
 * Auth store — holds JWT and user in memory only.
 * Intentionally not persisted to localStorage to reduce XSS exposure.
 * On refresh, user must re-authenticate.
 */
const STORAGE_KEY = 'sc_auth'

function loadFromStorage() {
  try {
    const raw = localStorage.getItem(STORAGE_KEY)
    return raw ? JSON.parse(raw) : null
  } catch {
    return null
  }
}

export const useAuthStore = defineStore('auth', () => {
  const stored = loadFromStorage()
  const jwt = ref(stored?.jwt ?? null)
  const user = ref(stored?.user ?? null)
  const role = ref(stored?.role ?? null)

  const isAuthenticated = computed(() => !!jwt.value)
  const isDoctor = computed(() => role.value === 'doctor')
  const isStaff = computed(() => ['staff', 'doctor', 'admin'].includes(role.value))

  function setAuth(token, userData) {
    jwt.value = token
    user.value = userData
    try {
      const payload = JSON.parse(atob(token.split('.')[1]))
      role.value = payload['custom:role'] ?? payload.role ?? null
    } catch {
      role.value = null
    }
    localStorage.setItem(STORAGE_KEY, JSON.stringify({ jwt: jwt.value, user: user.value, role: role.value }))
  }

  function clearAuth() {
    jwt.value = null
    user.value = null
    role.value = null
    localStorage.removeItem(STORAGE_KEY)
  }

  return { jwt, user, role, isAuthenticated, isDoctor, isStaff, setAuth, clearAuth }
})
