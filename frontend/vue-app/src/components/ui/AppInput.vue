<script setup>
defineProps({
  id:           { type: String,  required: true },
  label:        { type: String,  required: true },
  modelValue:   { type: String,  default: '' },
  type:         { type: String,  default: 'text' },
  autocomplete: { type: String,  default: 'off' },
  placeholder:  { type: String,  default: '' },
  error:        { type: String,  default: '' },
})

defineEmits(['update:modelValue'])
</script>

<template>
  <div class="flex flex-col gap-1.5">
    <label
      :for="id"
      class="text-sm font-medium text-text"
    >
      {{ label }}
    </label>

    <input
      :id="id"
      :type="type"
      :value="modelValue"
      :autocomplete="autocomplete"
      :placeholder="placeholder"
      :aria-describedby="error ? `${id}-error` : undefined"
      :aria-invalid="error ? 'true' : undefined"
      class="w-full px-4 py-3 text-base bg-white border rounded-lg
             text-text placeholder:text-slate-400
             transition-colors duration-200
             focus:outline-none focus:border-primary focus:ring-2 focus:ring-primary/25"
      :class="error
        ? 'border-red-400 focus:border-red-500 focus:ring-red-400/25'
        : 'border-slate-200 hover:border-slate-300'"
      @input="$emit('update:modelValue', $event.target.value)"
    />

    <p
      v-if="error"
      :id="`${id}-error`"
      role="alert"
      class="text-sm text-red-600 text-pretty"
    >
      {{ error }}
    </p>
  </div>
</template>
