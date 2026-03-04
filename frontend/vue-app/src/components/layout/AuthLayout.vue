<script setup>
defineProps({
  subtitle: { type: String, default: '' },
})
</script>

<!--
  Shared layout for all unauthenticated screens (Login, Sign Up).
  Provides: background, centered card, clinic logo, title/subtitle.
  Slot: form content.
-->
<template>
  <a
    href="#auth-form"
    class="sr-only focus:not-sr-only focus:fixed focus:top-4 focus:left-4
           focus:z-50 focus:px-4 focus:py-2 focus:bg-white focus:text-primary
           focus:rounded-lg focus:shadow-md focus:font-medium"
  >
    Skip to form
  </a>

  <main
    class="min-h-dvh flex flex-col items-center justify-center
           bg-surface px-4 py-12"
  >
    <div class="w-full max-w-sm bg-white rounded-2xl shadow-md px-6 py-10 sm:px-8">

      <!-- Clinic branding -->
      <header class="mb-8 text-center">
        <div
          class="mx-auto mb-4 w-12 h-12 rounded-xl bg-primary
                 flex items-center justify-center"
          aria-hidden="true"
        >
          <!-- Medical cross (Heroicons: plus) -->
          <svg
            xmlns="http://www.w3.org/2000/svg"
            viewBox="0 0 24 24"
            fill="currentColor"
            class="w-6 h-6 text-white"
          >
            <path
              fill-rule="evenodd"
              d="M12 3.75a.75.75 0 0 1 .75.75v6.75h6.75a.75.75 0 0 1 0 1.5h-6.75v6.75a.75.75 0 0 1-1.5 0v-6.75H4.5a.75.75 0 0 1 0-1.5h6.75V4.5a.75.75 0 0 1 .75-.75Z"
              clip-rule="evenodd"
            />
          </svg>
        </div>

        <h1 class="text-2xl font-semibold text-balance text-text">Smart Clinic Queue</h1>
        <p v-if="subtitle" class="mt-1 text-sm text-slate-500 text-pretty">
          {{ subtitle }}
        </p>
      </header>

      <!-- Page content (form, errors, links) -->
      <div id="auth-form">
        <slot />
      </div>

    </div>
  </main>
</template>
