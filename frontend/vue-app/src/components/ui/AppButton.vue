<script setup>
import { computed } from 'vue'

const props = defineProps({
  type:     { type: String,  default: 'button' },
  loading:  { type: Boolean, default: false },
  disabled: { type: Boolean, default: false },
  /**
   * 'primary'   — filled CTA (submit, confirm)
   * 'secondary' — outlined (cancel, back)
   */
  variant:  { type: String,  default: 'primary' },
})

const VARIANT_CLASSES = {
  primary:   'bg-cta text-white hover:bg-emerald-700 focus-visible:outline-cta',
  secondary: 'bg-transparent text-primary border-2 border-primary hover:bg-primary/10 focus-visible:outline-primary',
}

const variantClass = computed(() => VARIANT_CLASSES[props.variant] ?? VARIANT_CLASSES.primary)
</script>

<template>
  <button
    :type="type"
    :disabled="loading || disabled"
    :aria-busy="loading"
    class="flex items-center justify-center gap-2 w-full px-6 py-3
           text-base font-semibold rounded-lg cursor-pointer
           transition-all duration-200
           focus-visible:outline-3 focus-visible:outline-offset-2
           disabled:opacity-60 disabled:cursor-not-allowed"
    :class="variantClass"
  >
    <!-- Accessible spinner shown during async operations -->
    <svg
      v-if="loading"
      class="w-4 h-4 animate-spin"
      xmlns="http://www.w3.org/2000/svg"
      fill="none"
      viewBox="0 0 24 24"
      aria-hidden="true"
    >
      <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4" />
      <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z" />
    </svg>

    <slot />
  </button>
</template>
