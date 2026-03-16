import { createApp } from 'vue'
import { createPinia } from 'pinia'
import '@fontsource-variable/inter'
import App from './App.vue'
import router from './router'
import './style.css'

const app = createApp(App)

app.config.errorHandler = (err, instance, info) => {
  console.error('[Vue error]', info, err, instance)
}

window.addEventListener('unhandledrejection', (event) => {
  console.error('[Unhandled rejection]', event.reason)
})

app.use(createPinia())
app.use(router)
app.mount('#app')

import { registerServiceWorker } from './registerSW'
registerServiceWorker()
