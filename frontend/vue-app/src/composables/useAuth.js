import { ref } from 'vue'
import { useRouter } from 'vue-router'
import { useAuthStore } from '@/stores/auth'

const API_BASE = import.meta.env.VITE_API_BASE_URL ?? ''

/**
 * Exchanges a BetterAuth session token for a signed JWT.
 * @param {string} sessionToken
 * @returns {Promise<string>} JWT
 */
async function _exchangeForJwt(sessionToken) {
  const res = await fetch(`${API_BASE}/api/auth/token`, {
    headers: { Authorization: `Bearer ${sessionToken}` },
  })
  if (!res.ok) throw new Error('Could not obtain access token. Please try again.')
  const { token } = await res.json()
  return token
}

/**
 * Composable encapsulating all auth side-effects.
 * Keeps API calls out of components and the Pinia store.
 */
export function useAuth() {
  const authStore = useAuthStore()
  const router = useRouter()

  const loading = ref(false)
  const error = ref('')

  /**
   * Wraps any auth operation with shared loading/error/finally handling.
   * @param {() => Promise<void>} fn
   */
  async function _withAuthFlow(fn) {
    loading.value = true
    error.value = ''
    try {
      await fn()
    } catch (e) {
      error.value = e.message
    } finally {
      loading.value = false
    }
  }

  function signIn(email, password) {
    return _withAuthFlow(async () => {
      const res = await fetch(`${API_BASE}/api/auth/sign-in/email`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ email, password }),
      })

      if (!res.ok) {
        throw new Error(
          res.status === 401 ? 'Incorrect email or password.' : 'Something went wrong. Please try again.'
        )
      }

      const { token: sessionToken, user } = await res.json()
      const jwt = await _exchangeForJwt(sessionToken)
      authStore.setAuth(jwt, user)
      router.push('/dashboard')
    })
  }

  function signUp(name, email, password) {
    return _withAuthFlow(async () => {
      const res = await fetch(`${API_BASE}/api/auth/sign-up/email`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ name, email, password }),
      })

      if (!res.ok) {
        const body = await res.json().catch(() => ({}))
        throw new Error(body?.message ?? 'Registration failed. Please try again.')
      }

      const { token: sessionToken, user } = await res.json()
      const jwt = await _exchangeForJwt(sessionToken)
      authStore.setAuth(jwt, user)
      router.push('/dashboard')
    })
  }

  function signOut() {
    authStore.clearAuth()
    router.push('/login')
  }

  return { signIn, signUp, signOut, loading, error }
}
