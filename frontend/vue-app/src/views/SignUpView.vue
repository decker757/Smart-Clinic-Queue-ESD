<script setup>
import { ref } from 'vue'
import { useAuth } from '@/composables/useAuth'
import { isValidEmail } from '@/utils/validators'
import AuthLayout from '@/components/layout/AuthLayout.vue'
import AppAlert from '@/components/ui/AppAlert.vue'
import AppInput from '@/components/ui/AppInput.vue'
import AppButton from '@/components/ui/AppButton.vue'

const { signUp, loading, error } = useAuth()

const name            = ref('')
const email           = ref('')
const password        = ref('')
const confirmPassword = ref('')

const fieldErrors = ref({ name: '', email: '', password: '', confirmPassword: '' })

function validate() {
  fieldErrors.value = { name: '', email: '', password: '', confirmPassword: '' }
  let valid = true

  if (!name.value.trim()) {
    fieldErrors.value.name = 'Full name is required.'
    valid = false
  }

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
  } else if (password.value.length < 8) {
    fieldErrors.value.password = 'Password must be at least 8 characters.'
    valid = false
  }

  if (!confirmPassword.value) {
    fieldErrors.value.confirmPassword = 'Please confirm your password.'
    valid = false
  } else if (confirmPassword.value !== password.value) {
    fieldErrors.value.confirmPassword = 'Passwords do not match.'
    valid = false
  }

  return valid
}

async function handleSubmit() {
  if (!validate()) return
  await signUp(name.value.trim(), email.value.trim(), password.value)
}
</script>

<template>
  <AuthLayout subtitle="Create your account">

    <AppAlert v-if="error" :message="error" class="mb-5" />

    <form novalidate class="flex flex-col gap-5" @submit.prevent="handleSubmit">
      <AppInput
        id="name"
        label="Full name"
        type="text"
        v-model="name"
        autocomplete="name"
        placeholder="Jane Doe"
        :error="fieldErrors.name"
      />

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
        autocomplete="new-password"
        placeholder="Min. 8 characters"
        :error="fieldErrors.password"
      />

      <AppInput
        id="confirm-password"
        label="Confirm password"
        type="password"
        v-model="confirmPassword"
        autocomplete="new-password"
        :error="fieldErrors.confirmPassword"
      />

      <AppButton type="submit" :loading="loading" class="mt-1">
        {{ loading ? 'Creating account…' : 'Create account' }}
      </AppButton>
    </form>

    <p class="mt-6 text-center text-sm text-slate-500">
      Already have an account?
      <RouterLink
        to="/login"
        class="font-medium text-primary underline-offset-4 hover:underline"
      >
        Sign in
      </RouterLink>
    </p>

  </AuthLayout>
</template>
