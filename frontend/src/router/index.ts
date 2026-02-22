import { createRouter, createWebHistory } from 'vue-router'
import { useAuthStore } from '@/stores'
import AuthenticatedLayout from '@/layouts/AuthenticatedLayout.vue'
import HomePage from '@/pages/HomePage.vue'
import ProfilePage from '@/pages/ProfilePage.vue'
import EventsPage from '@/pages/EventsPage.vue'
import EventCreatePage from '@/pages/EventCreatePage.vue'
import EventEditPage from '@/pages/EventEditPage.vue'
import EventRedirectPage from '@/pages/EventRedirectPage.vue'
import EventPlanningPage from '@/pages/EventPlanningPage.vue'
import EventPlanningVotePage from '@/pages/EventPlanningVotePage.vue'
import EventPlanningDateRangesPage from '@/pages/EventPlanningDateRangesPage.vue'
import EventRsvpPage from '@/pages/EventRsvpPage.vue'
import MembersPage from '@/pages/MembersPage.vue'
import TasksPage from '@/pages/TasksPage.vue'
import EventExpensesPage from '@/pages/EventExpensesPage.vue'
import LoginPage from '@/pages/LoginPage.vue'
import AuthVerifyPage from '@/pages/AuthVerifyPage.vue'

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
        {
          path: 'profile',
          name: 'profile',
          component: ProfilePage,
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
          name: 'event-redirect',
          component: EventRedirectPage,
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
          path: 'events/:id/edit',
          name: 'event-edit',
          component: EventEditPage,
        },
        {
          path: 'events/:id/expenses',
          name: 'event-expenses',
          component: EventExpensesPage,
        },
        {
          path: 'tasks',
          name: 'tasks',
          component: TasksPage,
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
      meta: { requiresGuest: true },
    },
    {
      path: '/auth/verify',
      name: 'auth-verify',
      component: AuthVerifyPage,
    },
  ],
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
