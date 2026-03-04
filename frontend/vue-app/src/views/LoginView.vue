<script setup>
import { ref } from 'vue'
import { useAuth } from '@/composables/useAuth'
import { isValidEmail } from '@/utils/validators'
import AuthLayout from '@/components/layout/AuthLayout.vue'
import AppAlert from '@/components/ui/AppAlert.vue'
import AppInput from '@/components/ui/AppInput.vue'
import AppButton from '@/components/ui/AppButton.vue'

const { signIn, loading, error } = useAuth()

const email    = ref('')
const password = ref('')
const fieldErrors = ref({ email: '', password: '' })

function validate() {
  fieldErrors.value = { email: '', password: '' }
  let valid = true

  if (!email.value.trim()) {
    fieldErrors.value.email = 'Email is required.'
    valid = false
  } else if (!isValidEmail(email.value)) {
    fieldErrors.value.email = 'Enter a valid email address.'
    valid = false
  }

  if (!password.value) {
    fieldErrors.value.password = 'Password is required.'
    valid = false
  }

  return valid
}

async function handleSubmit() {
  if (!validate()) return
  await signIn(email.value.trim(), password.value)
}
</script>

<template>
  <AuthLayout subtitle="Sign in to access your appointment">

    <AppAlert v-if="error" :message="error" class="mb-5" />

    <form novalidate class="flex flex-col gap-5" @submit.prevent="handleSubmit">
      <AppInput
        id="email"
        label="Email address"
        type="email"
        v-model="email"
        autocomplete="email"
        placeholder="you@example.com"
        :error="fieldErrors.email"
      />

      <AppInput
        id="password"
        label="Password"
        type="password"
        v-model="password"
        autocomplete="current-password"
        :error="fieldErrors.password"
      />

      <AppButton type="submit" :loading="loading" class="mt-1">
        {{ loading ? 'Signing in…' : 'Sign in' }}
      </AppButton>
    </form>

    <p class="mt-6 text-center text-sm text-slate-500">
      Don't have an account?
      <RouterLink
        to="/signup"
        class="font-medium text-primary underline-offset-4 hover:underline"
      >
        Create account
      </RouterLink>
    </p>

  </AuthLayout>
</template>
