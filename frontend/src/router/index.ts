import { createRouter, createWebHistory } from 'vue-router'
import { useAuth } from '@/composables/useAuth'
import AuthenticatedLayout from '@/layouts/AuthenticatedLayout.vue'
import HomePage from '@/pages/HomePage.vue'
import ProfilePage from '@/pages/ProfilePage.vue'
import EventsPage from '@/pages/EventsPage.vue'
import EventCreatePage from '@/pages/EventCreatePage.vue'
import EventEditPage from '@/pages/EventEditPage.vue'
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
          path: 'events/:id/edit',
          name: 'events-edit',
          component: EventEditPage,
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
  const { isAuthenticated, initialized, initialize } = useAuth()

  if (!initialized.value) {
    await initialize()
  }

  if (to.meta.requiresAuth && !isAuthenticated.value) {
    next({ name: 'login' })
  } else if (to.meta.requiresGuest && isAuthenticated.value) {
    next({ name: 'home' })
  } else {
    next()
  }
})

export default router
