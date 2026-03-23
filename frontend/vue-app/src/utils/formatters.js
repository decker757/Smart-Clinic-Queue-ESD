const GENDER_MAP = { M: 'Male', F: 'Female' }

export function formatGender(code) {
  return GENDER_MAP[code] ?? code ?? '—'
}

export function formatDOB(dob) {
  if (!dob) return '—'
  return new Date(dob).toLocaleDateString('en-GB', { day: 'numeric', month: 'short', year: 'numeric' })
}
