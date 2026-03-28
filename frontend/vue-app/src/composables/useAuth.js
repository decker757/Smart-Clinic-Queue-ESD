import { ref } from 'vue'
import { useRouter } from 'vue-router'
import { useAuthStore } from '@/stores/auth'

const COGNITO_CLIENT_ID = '4iboa3a11vktthtupoidetvk9o'
const COGNITO_ENDPOINT = 'https://cognito-idp.ap-southeast-1.amazonaws.com/'

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

function friendlyError(e) {
  const code = e.code ?? ''
  if (code === 'NotAuthorizedException') return 'Incorrect email or password.'
  if (code === 'UserNotFoundException') return 'No account found with this email.'
  if (code === 'UsernameExistsException') return 'An account with this email already exists.'
  if (code === 'InvalidPasswordException') return e.message
  if (code === 'CodeMismatchException') return 'Incorrect verification code.'
  if (code === 'ExpiredCodeException') return 'Verification code expired. Please request a new one.'
  if (code === 'LimitExceededException') return 'Too many attempts. Please wait a moment and try again.'
  return e.message ?? 'Something went wrong. Please try again.'
}

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

  function signIn(email, password) {
    return _withAuthFlow(async () => {
      const data = await cognitoRequest('InitiateAuth', {
        AuthFlow: 'USER_PASSWORD_AUTH',
        ClientId: COGNITO_CLIENT_ID,
        AuthParameters: { USERNAME: email, PASSWORD: password },
      })
      const idToken = data.AuthenticationResult.IdToken
      const payload = JSON.parse(atob(idToken.split('.')[1]))
      authStore.setAuth(idToken, { email, name: payload.name ?? email })
      _redirectAfterLogin()
    })
  }

  function signUp(name, email, password) {
    return _withAuthFlow(async () => {
      await cognitoRequest('SignUp', {
        ClientId: COGNITO_CLIENT_ID,
        Username: crypto.randomUUID(),
        Password: password,
        UserAttributes: [
          { Name: 'email', Value: email },
          { Name: 'name', Value: name },
          { Name: 'custom:role', Value: 'patient' },
        ],
      })
      router.push('/login')
    })
  }

  function signOut() {
    authStore.clearAuth()
    router.push('/login')
  }

  return { signIn, signUp, signOut, loading, error }
}
