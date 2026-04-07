<script setup>
import { ref, onMounted } from 'vue'
import { useRouter } from 'vue-router'
import { useAuthStore } from '@/stores/auth'
import { apiError } from '@/utils/api'

const router = useRouter()
const authStore = useAuthStore()

const API_BASE = import.meta.env.VITE_API_BASE_URL ?? ''

// ─── State ───────────────────────────────────────────────────────────────────
const memos = ref([])
const loading = ref(true)
const fetchError = ref('')
const submitError = ref('')
const submitting = ref(false)

// Text memo form
const showTextForm = ref(false)
const textTitle = ref('')
const textContent = ref('')

// File upload form
const showFileForm = ref(false)
const fileTitle = ref('')
const selectedFile = ref(null)
const fileInputRef = ref(null)

// Expanded memo
const expandedId = ref(null)
function toggleMemo(id) {
  expandedId.value = expandedId.value === id ? null : id
}

// ─── Helpers ─────────────────────────────────────────────────────────────────
function authHeaders() {
  return { Authorization: `Bearer ${authStore.jwt}` }
}

function patientId() {
  return authStore.user?.id
}

function formatDate(iso) {
  return new Date(iso).toLocaleDateString('en-SG', {
    day: 'numeric', month: 'short', year: 'numeric',
  })
}

function fileIcon(fileType) {
  if (!fileType) return 'doc'
  if (fileType.startsWith('image/')) return 'img'
  if (fileType === 'application/pdf') return 'pdf'
  return 'doc'
}

// ─── Fetch ───────────────────────────────────────────────────────────────────
async function loadMemos() {
  loading.value = true
  fetchError.value = ''
  try {
    const res = await fetch(`${API_BASE}/api/composite/patients/${patientId()}/memos`, {
      headers: authHeaders(),
    })
    if (res.status === 404) { memos.value = []; return }
    if (!res.ok) throw new Error(`Failed to load records (${res.status})`)
    // Show all record types: patient memos, doctor-issued MC, and prescriptions
    memos.value = ((await res.json()) ?? [])
  } catch (e) {
    fetchError.value = e.message ?? 'Could not load medical records.'
  } finally {
    loading.value = false
  }
}

// Resolve file URLs: relative paths (from local Docker uploads) need the API
// base prepended so the browser can reach them through Kong.
function resolveFileUrl(url) {
  if (!url) return url
  if (url.startsWith('http://') || url.startsWith('https://')) return url
  return `${API_BASE}${url}`
}

async function openFile(memo) {
  if (!memo?.file_url) return

  const url = resolveFileUrl(memo.file_url)
  if (/^https?:\/\//.test(memo.file_url)) {
    window.open(url, '_blank', 'noopener,noreferrer')
    return
  }

  submitError.value = ''
  try {
    const res = await fetch(url, { headers: authHeaders() })
    if (!res.ok) {
      const body = await res.json().catch(() => ({}))
      throw new Error(apiError(body, 'Could not open file'))
    }

    const blob = await res.blob()
    const objectUrl = URL.createObjectURL(blob)
    const opened = window.open(objectUrl, '_blank', 'noopener,noreferrer')
    if (!opened) {
      URL.revokeObjectURL(objectUrl)
      throw new Error('Browser blocked the file preview')
    }
    setTimeout(() => URL.revokeObjectURL(objectUrl), 60_000)
  } catch (e) {
    submitError.value = e.message ?? 'Could not open file'
  }
}

function recordLabel(type) {
  if (type === 'mc') return 'Medical Certificate'
  if (type === 'prescription') return 'Prescription'
  return 'Note'
}

function recordLabelClass(type) {
  if (type === 'mc') return 'bg-blue-50 text-blue-700'
  if (type === 'prescription') return 'bg-amber-50 text-amber-700'
  return 'bg-slate-50 text-slate-500'
}

onMounted(() => {
  if (!patientId()) { router.push('/login'); return }
  loadMemos()
})

// ─── Submit text memo ─────────────────────────────────────────────────────────
async function submitText() {
  if (!textTitle.value.trim() || !textContent.value.trim()) return
  submitError.value = ''
  submitting.value = true
  try {
    const res = await fetch(`${API_BASE}/api/composite/patients/${patientId()}/memos`, {
      method: 'POST',
      headers: { ...authHeaders(), 'Content-Type': 'application/json' },
      body: JSON.stringify({ title: textTitle.value.trim(), content: textContent.value.trim() }),
    })
    if (!res.ok) {
      const body = await res.json().catch(() => ({}))
      throw new Error(body.detail ?? body.error ?? 'Failed to save note')
    }
    const memo = await res.json()
    memos.value.unshift(memo)
    textTitle.value = ''
    textContent.value = ''
    showTextForm.value = false
  } catch (e) {
    submitError.value = e.message
  } finally {
    submitting.value = false
  }
}

// ─── Submit file upload ───────────────────────────────────────────────────────
function onFileChange(e) {
  selectedFile.value = e.target.files[0] ?? null
}

async function submitFile() {
  if (!fileTitle.value.trim() || !selectedFile.value) return
  submitError.value = ''
  submitting.value = true
  try {
    const form = new FormData()
    form.append('title', fileTitle.value.trim())
    form.append('file', selectedFile.value)

    const res = await fetch(`${API_BASE}/api/composite/patients/${patientId()}/memos/upload`, {
      method: 'POST',
      headers: authHeaders(),  // no Content-Type — browser sets multipart boundary
      body: form,
    })
    if (!res.ok) {
      const body = await res.json().catch(() => ({}))
      throw new Error(body.detail ?? body.error ?? 'Upload failed')
    }
    const memo = await res.json()
    memos.value.unshift(memo)
    fileTitle.value = ''
    selectedFile.value = null
    if (fileInputRef.value) fileInputRef.value.value = ''
    showFileForm.value = false
  } catch (e) {
    submitError.value = e.message
  } finally {
    submitting.value = false
  }
}

function cancelForms() {
  showTextForm.value = false
  showFileForm.value = false
  submitError.value = ''
  textTitle.value = ''
  textContent.value = ''
  fileTitle.value = ''
  selectedFile.value = null
  if (fileInputRef.value) fileInputRef.value.value = ''
}
</script>

<template>
  <div class="min-h-dvh bg-surface">

    <!-- ─── Top Navigation ──────────────────────────────────────────────────── -->
    <header class="sticky top-0 z-20 bg-white border-b border-slate-200">
      <div class="max-w-2xl mx-auto px-4 h-14 flex items-center gap-3">
        <button
          type="button"
          class="flex items-center justify-center w-8 h-8 rounded-lg text-slate-500 hover:text-text hover:bg-slate-100 transition-colors duration-150 cursor-pointer"
          aria-label="Back to dashboard"
          @click="router.push('/dashboard')"
        >
          <svg class="w-5 h-5" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.75" aria-hidden="true">
            <path stroke-linecap="round" stroke-linejoin="round" d="M15.75 19.5 8.25 12l7.5-7.5" />
          </svg>
        </button>
        <h1 class="font-heading font-semibold text-text text-base">Medical Records</h1>
      </div>
    </header>

    <!-- ─── Main ────────────────────────────────────────────────────────────── -->
    <main class="max-w-2xl mx-auto px-4 py-6 space-y-5">

      <!-- Add actions -->
      <div v-if="!showTextForm && !showFileForm" class="flex gap-2">
        <button
          type="button"
          class="flex items-center gap-1.5 px-4 py-2 bg-cta text-white text-sm font-semibold rounded-xl hover:bg-cta/90 transition-colors duration-150 cursor-pointer"
          @click="showTextForm = true"
        >
          <svg class="w-4 h-4" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true">
            <path stroke-linecap="round" stroke-linejoin="round" d="M12 4.5v15m7.5-7.5h-15" />
          </svg>
          Add Note
        </button>
        <button
          type="button"
          class="flex items-center gap-1.5 px-4 py-2 bg-white border border-slate-200 text-sm font-semibold text-text rounded-xl hover:border-primary hover:text-primary transition-colors duration-150 cursor-pointer"
          @click="showFileForm = true"
        >
          <svg class="w-4 h-4" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.75" aria-hidden="true">
            <path stroke-linecap="round" stroke-linejoin="round" d="M3 16.5v2.25A2.25 2.25 0 0 0 5.25 21h13.5A2.25 2.25 0 0 0 21 18.75V16.5m-13.5-9L12 3m0 0 4.5 4.5M12 3v13.5" />
          </svg>
          Upload File
        </button>
      </div>

      <!-- Submit error -->
      <div
        v-if="submitError"
        role="alert"
        class="px-4 py-3 bg-red-50 border border-red-200 rounded-xl text-sm text-red-700"
      >
        {{ submitError }}
      </div>

      <!-- ─── Text note form ─────────────────────────────────────────────── -->
      <div v-if="showTextForm" class="bg-white rounded-2xl border border-slate-200 p-5 space-y-4">
        <h2 class="font-heading font-semibold text-text text-sm">New Note</h2>
        <div class="space-y-3">
          <div>
            <label class="block text-xs font-medium text-slate-600 mb-1" for="note-title">Title</label>
            <input
              id="note-title"
              v-model="textTitle"
              type="text"
              placeholder="e.g. Allergy reaction — 12 Mar 2026"
              class="w-full px-3 py-2 text-sm border border-slate-200 rounded-xl focus:outline-none focus:ring-2 focus:ring-primary/30 focus:border-primary transition-colors"
            />
          </div>
          <div>
            <label class="block text-xs font-medium text-slate-600 mb-1" for="note-content">Content</label>
            <textarea
              id="note-content"
              v-model="textContent"
              rows="4"
              placeholder="Describe symptoms, medication, or any notes…"
              class="w-full px-3 py-2 text-sm border border-slate-200 rounded-xl resize-none focus:outline-none focus:ring-2 focus:ring-primary/30 focus:border-primary transition-colors"
            />
          </div>
        </div>
        <div class="flex gap-2">
          <button
            type="button"
            class="px-4 py-2 bg-cta text-white text-sm font-semibold rounded-xl hover:bg-cta/90 disabled:opacity-50 transition-colors duration-150 cursor-pointer"
            :disabled="submitting || !textTitle.trim() || !textContent.trim()"
            @click="submitText"
          >
            {{ submitting ? 'Saving…' : 'Save Note' }}
          </button>
          <button
            type="button"
            class="px-4 py-2 text-sm text-slate-500 hover:text-text transition-colors duration-150 cursor-pointer"
            @click="cancelForms"
          >
            Cancel
          </button>
        </div>
      </div>

      <!-- ─── File upload form ───────────────────────────────────────────── -->
      <div v-if="showFileForm" class="bg-white rounded-2xl border border-slate-200 p-5 space-y-4">
        <h2 class="font-heading font-semibold text-text text-sm">Upload File</h2>
        <div class="space-y-3">
          <div>
            <label class="block text-xs font-medium text-slate-600 mb-1" for="file-title">Title</label>
            <input
              id="file-title"
              v-model="fileTitle"
              type="text"
              placeholder="e.g. Blood test results — Feb 2026"
              class="w-full px-3 py-2 text-sm border border-slate-200 rounded-xl focus:outline-none focus:ring-2 focus:ring-primary/30 focus:border-primary transition-colors"
            />
          </div>
          <div>
            <label class="block text-xs font-medium text-slate-600 mb-1" for="file-input">File</label>
            <!-- Drop zone -->
            <label
              for="file-input"
              class="flex flex-col items-center justify-center gap-2 w-full h-28 border-2 border-dashed border-slate-200 rounded-xl cursor-pointer hover:border-primary hover:bg-primary/4 transition-colors duration-150"
              :class="{ 'border-primary bg-primary/4': selectedFile }"
            >
              <svg class="w-6 h-6 text-slate-400" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.75" aria-hidden="true">
                <path stroke-linecap="round" stroke-linejoin="round" d="M3 16.5v2.25A2.25 2.25 0 0 0 5.25 21h13.5A2.25 2.25 0 0 0 21 18.75V16.5m-13.5-9L12 3m0 0 4.5 4.5M12 3v13.5" />
              </svg>
              <span class="text-sm text-slate-500">
                {{ selectedFile ? selectedFile.name : 'Click to choose or drag a file' }}
              </span>
              <span v-if="!selectedFile" class="text-xs text-slate-400">PDF, PNG, JPG, DOC up to 10 MB</span>
              <input
                id="file-input"
                ref="fileInputRef"
                type="file"
                accept=".pdf,.png,.jpg,.jpeg,.doc,.docx"
                class="sr-only"
                @change="onFileChange"
              />
            </label>
          </div>
        </div>
        <div class="flex gap-2">
          <button
            type="button"
            class="px-4 py-2 bg-cta text-white text-sm font-semibold rounded-xl hover:bg-cta/90 disabled:opacity-50 transition-colors duration-150 cursor-pointer"
            :disabled="submitting || !fileTitle.trim() || !selectedFile"
            @click="submitFile"
          >
            {{ submitting ? 'Uploading…' : 'Upload' }}
          </button>
          <button
            type="button"
            class="px-4 py-2 text-sm text-slate-500 hover:text-text transition-colors duration-150 cursor-pointer"
            @click="cancelForms"
          >
            Cancel
          </button>
        </div>
      </div>

      <!-- ─── Fetch error ────────────────────────────────────────────────── -->
      <div
        v-if="fetchError"
        role="alert"
        class="px-4 py-3 bg-red-50 border border-red-200 rounded-xl text-sm text-red-700"
      >
        {{ fetchError }}
      </div>

      <!-- ─── Loading skeleton ───────────────────────────────────────────── -->
      <div v-if="loading" class="space-y-3 animate-pulse" aria-busy="true" aria-label="Loading records">
        <div v-for="n in 3" :key="n" class="bg-white rounded-2xl border border-slate-200 p-4 flex gap-3">
          <div class="w-10 h-10 bg-slate-100 rounded-xl shrink-0" />
          <div class="flex-1 space-y-2">
            <div class="h-4 w-40 bg-slate-100 rounded" />
            <div class="h-3 w-24 bg-slate-100 rounded" />
          </div>
        </div>
      </div>

      <!-- ─── Empty state ────────────────────────────────────────────────── -->
      <div
        v-else-if="!fetchError && memos.length === 0"
        class="bg-white rounded-2xl border border-slate-200 p-8 text-center"
      >
        <div class="w-14 h-14 rounded-2xl bg-primary/8 flex items-center justify-center mx-auto mb-4">
          <svg class="w-7 h-7 text-primary" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.75" aria-hidden="true">
            <path stroke-linecap="round" stroke-linejoin="round"
              d="M19.5 14.25v-2.625a3.375 3.375 0 0 0-3.375-3.375h-1.5A1.125 1.125 0 0 1 13.5 7.125v-1.5a3.375 3.375 0 0 0-3.375-3.375H8.25m0 12.75h7.5m-7.5 3H12M10.5 2.25H5.625c-.621 0-1.125.504-1.125 1.125v17.25c0 .621.504 1.125 1.125 1.125h12.75c.621 0 1.125-.504 1.125-1.125V11.25a9 9 0 0 0-9-9Z" />
          </svg>
        </div>
        <p class="font-heading font-semibold text-text text-base">No records yet</p>
        <p class="text-slate-500 text-sm mt-1">Add a note or upload a document to get started.</p>
      </div>

      <!-- ─── Memo list ──────────────────────────────────────────────────── -->
      <ul v-else class="space-y-3" aria-label="Medical records">
        <li
          v-for="memo in memos"
          :key="memo.id"
          class="bg-white rounded-2xl border border-slate-200 overflow-hidden"
        >
          <!-- Summary row (always visible) -->
          <button
            type="button"
            class="w-full text-left p-4 flex items-start gap-3 cursor-pointer hover:bg-slate-50 transition-colors duration-150"
            @click="toggleMemo(memo.id)"
          >
            <!-- Icon -->
            <div class="w-10 h-10 rounded-xl flex items-center justify-center shrink-0"
              :class="{
                'bg-blue-50': memo.record_type === 'mc',
                'bg-amber-50': memo.record_type === 'prescription',
                'bg-red-50': memo.record_type === 'memo' && fileIcon(memo.file_type) === 'pdf',
                'bg-primary/8': memo.record_type === 'memo' && memo.file_url && fileIcon(memo.file_type) !== 'pdf',
                'bg-slate-50': memo.record_type === 'memo' && !memo.file_url,
              }"
            >
              <!-- MC icon -->
              <svg v-if="memo.record_type === 'mc'" class="w-5 h-5 text-blue-500" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.75" aria-hidden="true">
                <path stroke-linecap="round" stroke-linejoin="round" d="M9 12h3.75M9 15h3.75M9 18h3.75m3 .75H18a2.25 2.25 0 0 0 2.25-2.25V6.108c0-1.135-.845-2.098-1.976-2.192a48.424 48.424 0 0 0-1.123-.08m-5.801 0c-.065.21-.1.433-.1.664 0 .414.336.75.75.75h4.5a.75.75 0 0 0 .75-.75 2.25 2.25 0 0 0-.1-.664m-5.8 0A2.251 2.251 0 0 1 13.5 2.25H15c1.012 0 1.867.668 2.15 1.586m-5.8 0c-.376.023-.75.05-1.124.08C9.095 4.01 8.25 4.973 8.25 6.108V8.25m0 0H4.875c-.621 0-1.125.504-1.125 1.125v11.25c0 .621.504 1.125 1.125 1.125h9.75c.621 0 1.125-.504 1.125-1.125V9.375c0-.621-.504-1.125-1.125-1.125H8.25Z" />
              </svg>
              <!-- Prescription icon -->
              <svg v-else-if="memo.record_type === 'prescription'" class="w-5 h-5 text-amber-600" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.75" aria-hidden="true">
                <path stroke-linecap="round" stroke-linejoin="round" d="M9.75 3.104v5.714a2.25 2.25 0 0 1-.659 1.591L5 14.5M9.75 3.104c-.251.023-.501.05-.75.082m.75-.082a24.301 24.301 0 0 1 4.5 0m0 0v5.714c0 .597.237 1.17.659 1.591L19.8 15.3M14.25 3.104c.251.023.501.05.75.082M19.8 15.3l-1.57.393A9.065 9.065 0 0 1 12 15a9.065 9.065 0 0 0-6.23.693L5 14.5m14.8.8 1.402 1.402c1.232 1.232.65 3.318-1.067 3.611A48.309 48.309 0 0 1 12 21c-2.773 0-5.491-.235-8.135-.687-1.718-.293-2.3-2.379-1.067-3.61L5 14.5" />
              </svg>
              <!-- Patient note icon (no file) -->
              <svg v-else-if="!memo.file_url" class="w-5 h-5 text-slate-400" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.75" aria-hidden="true">
                <path stroke-linecap="round" stroke-linejoin="round" d="M3.75 6.75h16.5M3.75 12h16.5m-16.5 5.25H12" />
              </svg>
              <svg v-else-if="fileIcon(memo.file_type) === 'img'" class="w-5 h-5 text-blue-500" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.75" aria-hidden="true">
                <path stroke-linecap="round" stroke-linejoin="round" d="m2.25 15.75 5.159-5.159a2.25 2.25 0 0 1 3.182 0l5.159 5.159m-1.5-1.5 1.409-1.409a2.25 2.25 0 0 1 3.182 0l2.909 2.909m-18 3.75h16.5a1.5 1.5 0 0 0 1.5-1.5V6a1.5 1.5 0 0 0-1.5-1.5H3.75A1.5 1.5 0 0 0 2.25 6v12a1.5 1.5 0 0 0 1.5 1.5Zm10.5-11.25h.008v.008h-.008V8.25Zm.375 0a.375.375 0 1 1-.75 0 .375.375 0 0 1 .75 0Z" />
              </svg>
              <svg v-else-if="fileIcon(memo.file_type) === 'pdf'" class="w-5 h-5 text-red-500" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.75" aria-hidden="true">
                <path stroke-linecap="round" stroke-linejoin="round" d="M19.5 14.25v-2.625a3.375 3.375 0 0 0-3.375-3.375h-1.5A1.125 1.125 0 0 1 13.5 7.125v-1.5a3.375 3.375 0 0 0-3.375-3.375H8.25m2.25 0H5.625c-.621 0-1.125.504-1.125 1.125v17.25c0 .621.504 1.125 1.125 1.125h12.75c.621 0 1.125-.504 1.125-1.125V11.25a9 9 0 0 0-9-9Z" />
              </svg>
              <svg v-else class="w-5 h-5 text-primary" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.75" aria-hidden="true">
                <path stroke-linecap="round" stroke-linejoin="round" d="M19.5 14.25v-2.625a3.375 3.375 0 0 0-3.375-3.375h-1.5A1.125 1.125 0 0 1 13.5 7.125v-1.5a3.375 3.375 0 0 0-3.375-3.375H8.25m0 12.75h7.5m-7.5 3H12M10.5 2.25H5.625c-.621 0-1.125.504-1.125 1.125v17.25c0 .621.504 1.125 1.125 1.125h12.75c.621 0 1.125-.504 1.125-1.125V11.25a9 9 0 0 0-9-9Z" />
              </svg>
            </div>

            <!-- Summary -->
            <div class="flex-1 min-w-0">
              <div class="flex items-center gap-2">
                <p class="font-semibold text-sm text-text truncate">{{ memo.title }}</p>
                <span
                  v-if="memo.record_type !== 'memo'"
                  class="shrink-0 text-[10px] font-semibold uppercase tracking-wide px-2 py-0.5 rounded-full"
                  :class="recordLabelClass(memo.record_type)"
                >
                  {{ recordLabel(memo.record_type) }}
                </span>
              </div>
              <p class="text-xs text-slate-400 mt-0.5">
                {{ formatDate(memo.created_at) }}
                <span v-if="memo.issued_by" class="text-slate-300"> · Issued by doctor</span>
              </p>
            </div>

            <!-- Chevron -->
            <svg
              class="w-4 h-4 text-slate-400 shrink-0 transition-transform duration-200"
              :class="expandedId === memo.id ? 'rotate-180' : ''"
              viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"
            >
              <path stroke-linecap="round" stroke-linejoin="round" d="m19 9-7 7-7-7" />
            </svg>
          </button>

          <!-- Expanded detail -->
          <div v-if="expandedId === memo.id" class="border-t border-slate-100 px-4 py-4 space-y-3">
            <p v-if="memo.content" class="text-sm text-text whitespace-pre-wrap">{{ memo.content }}</p>
            <button
              v-if="memo.file_url"
              type="button"
              class="inline-flex items-center gap-1.5 text-sm text-primary font-medium hover:underline"
              @click="openFile(memo)"
            >
              <svg class="w-4 h-4" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.75">
                <path stroke-linecap="round" stroke-linejoin="round" d="M13.5 6H5.25A2.25 2.25 0 0 0 3 8.25v10.5A2.25 2.25 0 0 0 5.25 21h10.5A2.25 2.25 0 0 0 18 18.75V10.5m-10.5 6L21 3m0 0h-5.25M21 3v5.25" />
              </svg>
              Open File
            </button>
          </div>
        </li>
      </ul>

    </main>
  </div>
</template>
