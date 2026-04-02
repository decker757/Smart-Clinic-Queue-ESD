import { ref } from 'vue'
import { useRouter } from 'vue-router'
import { useAuthStore } from '@/stores/auth'

// ─── Auth mode: "betterauth" (local dev) or "cognito" (production) ──────────
const AUTH_MODE = import.meta.env.VITE_AUTH_MODE ?? 'betterauth'
const API_BASE = import.meta.env.VITE_API_BASE_URL ?? ''

// ─── Cognito helpers (production only) ──────────────────────────────────────
const COGNITO_CLIENT_ID = import.meta.env.VITE_COGNITO_CLIENT_ID ?? ''
const COGNITO_ENDPOINT = import.meta.env.VITE_COGNITO_ENDPOINT ?? ''

async function cognitoRequest(target, body) {
  const res = await fetch(COGNITO_ENDPOINT, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/x-amz-json-1.1',
      'X-Amz-Target': `AWSCognitoIdentityProviderService.${target}`,
    },
    body: JSON.stringify(body),
  })
  const data = await res.json()
  if (!res.ok) throw Object.assign(new Error(data.message ?? 'Auth error'), { code: data.__type })
  return data
}

// ─── BetterAuth helpers (local dev) ─────────────────────────────────────────

async function betterAuthRequest(path, body) {
  const res = await fetch(`${API_BASE}/api/auth${path}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    credentials: 'include', // session cookie
    body: JSON.stringify(body),
  })
  const data = await res.json()
  if (!res.ok) {
    const msg = data?.message ?? data?.error ?? 'Auth error'
    throw Object.assign(new Error(msg), { code: data?.code ?? '' })
  }
  return data
}

async function betterAuthGetToken() {
  const res = await fetch(`${API_BASE}/api/auth/token`, {
    credentials: 'include',
  })
  const data = await res.json()
  if (!res.ok) throw new Error(data?.message ?? 'Failed to get token')
  return data.token
}

// ─── Friendly error mapping ─────────────────────────────────────────────────

function friendlyError(e) {
  const code = e.code ?? ''
  // Cognito error codes
  if (code === 'NotAuthorizedException') return 'Incorrect email or password.'
  if (code === 'UserNotFoundException') return 'No account found with this email.'
  if (code === 'UsernameExistsException') return 'An account with this email already exists.'
  if (code === 'InvalidPasswordException') return e.message
  if (code === 'CodeMismatchException') return 'Incorrect verification code.'
  if (code === 'ExpiredCodeException') return 'Verification code expired. Please request a new one.'
  if (code === 'LimitExceededException') return 'Too many attempts. Please wait a moment and try again.'
  // BetterAuth error codes
  if (code === 'INVALID_EMAIL_OR_PASSWORD') return 'Incorrect email or password.'
  if (code === 'USER_ALREADY_EXISTS') return 'An account with this email already exists.'
  return e.message ?? 'Something went wrong. Please try again.'
}

// ─── Composable ─────────────────────────────────────────────────────────────

export function useAuth() {
  const authStore = useAuthStore()
  const router = useRouter()

  const loading = ref(false)
  const error = ref('')

  async function _withAuthFlow(fn) {
    loading.value = true
    error.value = ''
    try {
      return await fn()
    } catch (e) {
      error.value = friendlyError(e)
    } finally {
      loading.value = false
    }
  }

  function _redirectAfterLogin() {
    if (authStore.isDoctor) router.push('/doctor-dashboard')
    else if (authStore.isStaff) router.push('/staff-dashboard')
    else router.push('/dashboard')
  }

  // ── Sign In ─────────────────────────────────────────────────

  function signIn(email, password) {
    return _withAuthFlow(async () => {
      if (AUTH_MODE === 'cognito') {
        const data = await cognitoRequest('InitiateAuth', {
          AuthFlow: 'USER_PASSWORD_AUTH',
          ClientId: COGNITO_CLIENT_ID,
          AuthParameters: { USERNAME: email, PASSWORD: password },
        })
        const idToken = data.AuthenticationResult.IdToken
        const payload = JSON.parse(atob(idToken.split('.')[1]))
        authStore.setAuth(idToken, { id: payload.sub, email, name: payload.name ?? email })
      } else {
        // BetterAuth: sign in → session cookie, then exchange for JWT
        await betterAuthRequest('/sign-in/email', { email, password })
        const jwt = await betterAuthGetToken()
        const payload = JSON.parse(atob(jwt.split('.')[1]))
        authStore.setAuth(jwt, {
          id: payload.sub,
          email,
          name: payload.name ?? email,
        })
      }
      _redirectAfterLogin()
    })
  }

  // ── Sign Up ─────────────────────────────────────────────────

  function signUp(name, email, password) {
    return _withAuthFlow(async () => {
      if (AUTH_MODE === 'cognito') {
        await cognitoRequest('SignUp', {
          ClientId: COGNITO_CLIENT_ID,
          Username: (crypto.randomUUID?.() ?? `${Date.now()}-${Math.random().toString(36).slice(2)}`),
          Password: password,
          UserAttributes: [
            { Name: 'email', Value: email },
            { Name: 'name', Value: name },
            { Name: 'custom:role', Value: 'patient' },
          ],
        })
      } else {
        // BetterAuth: create account
        await betterAuthRequest('/sign-up/email', { email, password, name })
      }
      router.push('/login')
    })
  }

  // ── Sign Out ────────────────────────────────────────────────

  function signOut() {
    authStore.clearAuth()
    window.location.replace('/login')
  }

  return { signIn, signUp, signOut, loading, error }
}
