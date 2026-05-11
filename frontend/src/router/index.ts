import { createRouter, createWebHistory } from 'vue-router'
import { useAuthStore } from '@/stores'
import AuthenticatedLayout from '@/layouts/AuthenticatedLayout.vue'

const HomePage = () => import('@/pages/HomePage.vue')
const SettingsLayout = () => import('@/layouts/SettingsLayout.vue')
const SettingsProfilePage = () => import('@/pages/SettingsProfilePage.vue')
const SettingsLoginPage = () => import('@/pages/SettingsLoginPage.vue')
const SettingsPaymentPage = () => import('@/pages/SettingsPaymentPage.vue')
const SettingsNotificationsPage = () =>
  import('@/pages/SettingsNotificationsPage.vue')
const EventsPage = () => import('@/pages/EventsPage.vue')
const EventCreatePage = () => import('@/pages/EventCreatePage.vue')
const EventPage = () => import('@/pages/EventPage.vue')
const EventPlanningPage = () => import('@/pages/EventPlanningPage.vue')
const EventPlanningVotePage = () => import('@/pages/EventPlanningVotePage.vue')
const EventPlanningDateRangesPage = () =>
  import('@/pages/EventPlanningDateRangesPage.vue')
const EventRsvpPage = () => import('@/pages/EventRsvpPage.vue')
const MembersPage = () => import('@/pages/MembersPage.vue')
const TasksPage = () => import('@/pages/TasksPage.vue')
const EventExpensesPage = () => import('@/pages/EventExpensesPage.vue')
const EventChoresPage = () => import('@/pages/EventChoresPage.vue')
const SettleUpPage = () => import('@/pages/SettleUpPage.vue')
const LoginPage = () => import('@/pages/LoginPage.vue')
const AuthVerifyPage = () => import('@/pages/AuthVerifyPage.vue')
const InviteAcceptPage = () => import('@/pages/InviteAcceptPage.vue')
const VerifyEmailChangePage = () => import('@/pages/VerifyEmailChangePage.vue')

const router = createRouter({
  history: createWebHistory(import.meta.env.BASE_URL),
  routes: [
    {
      path: '/',
      component: AuthenticatedLayout,
      meta: { requiresAuth: true },
      children: [
        {
          path: '',
          name: 'home',
          component: HomePage,
        },
        { path: 'profile', redirect: '/settings/profile' },
        { path: 'account', redirect: '/settings/login' },
        {
          path: 'settings',
          name: 'settings',
          component: SettingsLayout,
          children: [
            {
              path: 'profile',
              name: 'settings-profile',
              component: SettingsProfilePage,
            },
            {
              path: 'login',
              name: 'settings-login',
              component: SettingsLoginPage,
            },
            { path: 'account', redirect: '/settings/login' },
            { path: 'security', redirect: '/settings/login' },
            {
              path: 'payment',
              name: 'settings-payment',
              component: SettingsPaymentPage,
            },
            {
              path: 'notifications',
              name: 'settings-notifications',
              component: SettingsNotificationsPage,
            },
          ],
        },
        {
          path: 'events',
          name: 'events',
          component: EventsPage,
        },
        {
          path: 'events/new',
          name: 'events-new',
          component: EventCreatePage,
        },
        {
          path: 'events/:id',
          name: 'event',
          component: EventPage,
        },
        {
          path: 'events/:id/planning',
          name: 'event-planning',
          component: EventPlanningPage,
        },
        {
          path: 'events/:id/planning/vote',
          name: 'event-planning-vote',
          component: EventPlanningVotePage,
        },
        {
          path: 'events/:id/planning/date-ranges',
          name: 'event-planning-date-ranges',
          component: EventPlanningDateRangesPage,
        },
        {
          path: 'events/:id/rsvp',
          name: 'event-rsvp',
          component: EventRsvpPage,
        },
        {
          path: 'events/:id/expenses',
          name: 'event-expenses',
          component: EventExpensesPage,
        },
        {
          path: 'events/:id/chores',
          name: 'event-chores',
          component: EventChoresPage,
        },
        {
          path: 'tasks',
          name: 'tasks',
          component: TasksPage,
        },
        {
          path: 'settle-up',
          name: 'settle-up',
          component: SettleUpPage,
        },
        {
          path: 'members',
          name: 'members',
          component: MembersPage,
        },
      ],
    },
    {
      path: '/login',
      name: 'login',
      component: LoginPage,
      meta: { requiresGuest: true, title: 'Login' },
    },
    {
      path: '/auth/verify',
      name: 'auth-verify',
      component: AuthVerifyPage,
      meta: { title: 'Verifying' },
    },
    {
      path: '/invite/accept',
      name: 'invite-accept',
      component: InviteAcceptPage,
      meta: { title: 'Accept Invitation' },
    },
    {
      path: '/verify-email',
      name: 'verify-email',
      component: VerifyEmailChangePage,
      meta: { title: 'Verify Email' },
    },
  ],
})

export function isChunkLoadError(error: unknown): boolean {
  if (!(error instanceof Error)) return false
  return /Loading chunk|Failed to fetch dynamically imported module/.test(
    error.message
  )
}

router.onError((error) => {
  if (!isChunkLoadError(error)) return

  const reloadKey = 'chunk_load_error_reloaded'
  if (sessionStorage.getItem(reloadKey)) return

  sessionStorage.setItem(reloadKey, '1')
  window.location.reload()
})

router.afterEach((to) => {
  const title = to.meta.title as string | undefined
  if (title) {
    document.title = title
  }
})

router.beforeEach(async (to) => {
  const authStore = useAuthStore()

  // Initialize or re-initialize if token was added after initial load
  await authStore.initialize()

  if (to.meta.requiresAuth && !authStore.isAuthenticated) {
    return { name: 'login' }
  } else if (to.meta.requiresGuest && authStore.isAuthenticated) {
    return { name: 'home' }
  }
})

export default router
