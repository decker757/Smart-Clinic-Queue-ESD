import { createRouter, createWebHistory } from 'vue-router'
import { useAuthStore } from '@/stores/auth'

const router = createRouter({
  history: createWebHistory(import.meta.env.BASE_URL),
  routes: [
    {
      path: '/',
      redirect: '/login',
    },
    {
      path: '/login',
      name: 'login',
      component: () => import('@/views/LoginView.vue'),
      meta: { requiresAuth: false },
    },
    {
      path: '/signup',
      name: 'signup',
      component: () => import('@/views/SignUpView.vue'),
      meta: { requiresAuth: false },
    },
    {
      path: '/dashboard',
      name: 'dashboard',
      component: () => import('@/views/PatientDashboardView.vue'),
      meta: { requiresAuth: true },
    },
    {
      path: '/staff-dashboard',
      name: 'staff-dashboard',
      component: () => import('@/views/StaffDashboardView.vue'),
      meta: { requiresAuth: true, requiresStaff: true },
    },
    {
      path: '/records',
      name: 'records',
      component: () => import('@/views/MedicalRecordsView.vue'),
      meta: { requiresAuth: true },
    },
    {
      path: '/booking',
      name: 'booking',
      component: () => import('@/views/BookingView.vue'),
      meta: { requiresAuth: true },
    },
    {
      path: '/queue/:appointmentId',
      name: 'queue',
      component: () => import('@/views/PatientQueueView.vue'),
      meta: { requiresAuth: true },
    },
  ],
})

// Auth guard — redirects unauthenticated users to /login
router.beforeEach((to) => {
  const auth = useAuthStore()

  if (to.meta.requiresAuth && !auth.isAuthenticated) {
    return { name: 'login' }
  }

  // Staff trying to access patient pages — redirect to staff dashboard
  if (to.name === 'dashboard' && auth.isAuthenticated && auth.isStaff) {
    return { name: 'staff-dashboard' }
  }

  // Prevent authenticated users from visiting auth screens again
  const authScreens = ['login', 'signup']
  if (authScreens.includes(to.name) && auth.isAuthenticated) {
    return auth.isStaff ? { name: 'staff-dashboard' } : { name: 'dashboard' }
  }

  // Block non-staff from accessing staff pages
  if (to.meta.requiresStaff && !auth.isStaff) {
    return { name: 'dashboard' }
  }
})

export default router
