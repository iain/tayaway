import { createRouter, createWebHistory } from 'vue-router'
import { useAuthStore } from '@/stores'
import AuthenticatedLayout from '@/layouts/AuthenticatedLayout.vue'
import HomePage from '@/pages/HomePage.vue'
import ProfilePage from '@/pages/ProfilePage.vue'
import EventsPage from '@/pages/EventsPage.vue'
import EventCreatePage from '@/pages/EventCreatePage.vue'
import EventEditPage from '@/pages/EventEditPage.vue'
import EventPage from '@/pages/EventPage.vue'
import UsersPage from '@/pages/UsersPage.vue'
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
          name: 'event',
          component: EventPage,
        },
        {
          path: 'events/:id/edit',
          name: 'events-edit',
          component: EventEditPage,
        },
        {
          path: 'users',
          name: 'users',
          component: UsersPage,
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

router.beforeEach(async (to, _from, next) => {
  const authStore = useAuthStore()

  // Initialize or re-initialize if token was added after initial load
  await authStore.initialize()

  if (to.meta.requiresAuth && !authStore.isAuthenticated) {
    next({ name: 'login' })
  } else if (to.meta.requiresGuest && authStore.isAuthenticated) {
    next({ name: 'home' })
  } else {
    next()
  }
})

export default router
