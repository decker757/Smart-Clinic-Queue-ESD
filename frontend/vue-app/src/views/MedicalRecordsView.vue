<script setup>
import { ref, onMounted } from 'vue'
import { useRouter } from 'vue-router'
import { useAuthStore } from '@/stores/auth'

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
    const res = await fetch(`${API_BASE}/api/patients/${patientId()}/memos`, {
      headers: authHeaders(),
    })
    if (res.status === 404) { memos.value = []; return }
    if (!res.ok) throw new Error(`Failed to load records (${res.status})`)
    memos.value = (await res.json()) ?? []
  } catch (e) {
    fetchError.value = e.message ?? 'Could not load medical records.'
  } finally {
    loading.value = false
  }
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
    const res = await fetch(`${API_BASE}/api/patients/${patientId()}/memos`, {
      method: 'POST',
      headers: { ...authHeaders(), 'Content-Type': 'application/json' },
      body: JSON.stringify({ title: textTitle.value.trim(), content: textContent.value.trim() }),
    })
    if (!res.ok) {
      const body = await res.json().catch(() => ({}))
      throw new Error(body.error ?? 'Failed to save note')
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

    const res = await fetch(`${API_BASE}/api/patients/${patientId()}/memos/upload`, {
      method: 'POST',
      headers: authHeaders(),  // no Content-Type — browser sets multipart boundary
      body: form,
    })
    if (!res.ok) {
      const body = await res.json().catch(() => ({}))
      throw new Error(body.error ?? 'Upload failed')
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
          class="bg-white rounded-2xl border border-slate-200 p-4 flex items-start gap-3"
        >
          <!-- Icon -->
          <div class="w-10 h-10 rounded-xl flex items-center justify-center shrink-0"
            :class="{
              'bg-blue-50': fileIcon(memo.file_type) === 'img',
              'bg-red-50': fileIcon(memo.file_type) === 'pdf',
              'bg-primary/8': fileIcon(memo.file_type) === 'doc' && memo.file_url,
              'bg-slate-50': !memo.file_url,
            }"
          >
            <!-- Text note -->
            <svg v-if="!memo.file_url" class="w-5 h-5 text-slate-400" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.75" aria-hidden="true">
              <path stroke-linecap="round" stroke-linejoin="round" d="M3.75 6.75h16.5M3.75 12h16.5m-16.5 5.25H12" />
            </svg>
            <!-- Image -->
            <svg v-else-if="fileIcon(memo.file_type) === 'img'" class="w-5 h-5 text-blue-500" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.75" aria-hidden="true">
              <path stroke-linecap="round" stroke-linejoin="round" d="m2.25 15.75 5.159-5.159a2.25 2.25 0 0 1 3.182 0l5.159 5.159m-1.5-1.5 1.409-1.409a2.25 2.25 0 0 1 3.182 0l2.909 2.909m-18 3.75h16.5a1.5 1.5 0 0 0 1.5-1.5V6a1.5 1.5 0 0 0-1.5-1.5H3.75A1.5 1.5 0 0 0 2.25 6v12a1.5 1.5 0 0 0 1.5 1.5Zm10.5-11.25h.008v.008h-.008V8.25Zm.375 0a.375.375 0 1 1-.75 0 .375.375 0 0 1 .75 0Z" />
            </svg>
            <!-- PDF -->
            <svg v-else-if="fileIcon(memo.file_type) === 'pdf'" class="w-5 h-5 text-red-500" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.75" aria-hidden="true">
              <path stroke-linecap="round" stroke-linejoin="round" d="M19.5 14.25v-2.625a3.375 3.375 0 0 0-3.375-3.375h-1.5A1.125 1.125 0 0 1 13.5 7.125v-1.5a3.375 3.375 0 0 0-3.375-3.375H8.25m2.25 0H5.625c-.621 0-1.125.504-1.125 1.125v17.25c0 .621.504 1.125 1.125 1.125h12.75c.621 0 1.125-.504 1.125-1.125V11.25a9 9 0 0 0-9-9Z" />
            </svg>
            <!-- Generic doc -->
            <svg v-else class="w-5 h-5 text-primary" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.75" aria-hidden="true">
              <path stroke-linecap="round" stroke-linejoin="round" d="M19.5 14.25v-2.625a3.375 3.375 0 0 0-3.375-3.375h-1.5A1.125 1.125 0 0 1 13.5 7.125v-1.5a3.375 3.375 0 0 0-3.375-3.375H8.25m0 12.75h7.5m-7.5 3H12M10.5 2.25H5.625c-.621 0-1.125.504-1.125 1.125v17.25c0 .621.504 1.125 1.125 1.125h12.75c.621 0 1.125-.504 1.125-1.125V11.25a9 9 0 0 0-9-9Z" />
            </svg>
          </div>

          <!-- Content -->
          <div class="flex-1 min-w-0">
            <p class="font-semibold text-sm text-text truncate">{{ memo.title }}</p>
            <p v-if="memo.content" class="text-xs text-slate-500 mt-0.5 line-clamp-2">{{ memo.content }}</p>
            <p class="text-xs text-slate-400 mt-1">{{ formatDate(memo.created_at) }}</p>
          </div>

          <!-- Open file link -->
          <a
            v-if="memo.file_url"
            :href="memo.file_url"
            target="_blank"
            rel="noopener noreferrer"
            class="shrink-0 flex items-center justify-center w-8 h-8 rounded-lg text-slate-400 hover:text-primary hover:bg-primary/8 transition-colors duration-150"
            aria-label="Open file"
          >
            <svg class="w-4 h-4" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.75" aria-hidden="true">
              <path stroke-linecap="round" stroke-linejoin="round" d="M13.5 6H5.25A2.25 2.25 0 0 0 3 8.25v10.5A2.25 2.25 0 0 0 5.25 21h10.5A2.25 2.25 0 0 0 18 18.75V10.5m-10.5 6L21 3m0 0h-5.25M21 3v5.25" />
            </svg>
          </a>
        </li>
      </ul>

    </main>
  </div>
</template>
