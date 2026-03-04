<script setup>
defineProps({
  message: { type: String, required: true },
})
</script>

<template>
  <div
    role="alert"
    class="px-4 py-3 bg-red-50 border border-red-200 rounded-lg
           text-sm text-red-700 text-pretty"
  >
    {{ message }}
  </div>
</template>
