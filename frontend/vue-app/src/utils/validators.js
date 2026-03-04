// Compiled once at module load — not recreated per call
const EMAIL_REGEX = /^[^\s@]+@[^\s@]+\.[^\s@]+$/

export const isValidEmail = (email) => EMAIL_REGEX.test(email)
