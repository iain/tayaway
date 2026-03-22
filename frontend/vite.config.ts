import { defineConfig } from 'vite'
import vue from '@vitejs/plugin-vue'
import tailwindcss from '@tailwindcss/vite'
import { VitePWA } from 'vite-plugin-pwa'
import { fileURLToPath, URL } from 'node:url'

const port = parseInt(process.env.FRONTEND_PORT || '5173', 10)
const apiPort = process.env.API_PORT || '9292'

// https://vite.dev/config/
export default defineConfig({
  plugins: [
    vue(),
    tailwindcss(),
    VitePWA({
      registerType: 'prompt',
      manifest: {
        name: 'Tayaway',
        short_name: 'Tayaway',
        description: 'Collaborative event planning',
        theme_color: '#d97706',
        background_color: '#ffffff',
        display: 'standalone',
        icons: [
          { src: '/icon.svg', sizes: 'any', type: 'image/svg+xml' },
          { src: '/icon-192.png', sizes: '192x192', type: 'image/png' },
          { src: '/icon-512.png', sizes: '512x512', type: 'image/png' },
        ],
      },
      injectRegister: false,
      workbox: {
        globPatterns: ['**/*.{js,css,html,ico,png,svg,woff,woff2}'],
        navigateFallback: '/index.html',
        runtimeCaching: [
          {
            urlPattern: ({ url, request }) =>
              url.pathname === '/api/auth/me' && request.method === 'GET',
            handler: 'StaleWhileRevalidate',
            options: {
              cacheName: 'api-auth',
            },
          },
          {
            urlPattern: ({ url, request }) =>
              url.pathname.startsWith('/api/') && request.method === 'GET',
            handler: 'NetworkFirst',
            options: {
              cacheName: 'api-data',
              networkTimeoutSeconds: 3,
            },
          },
        ],
      },
    }),
  ],
  build: {
    rollupOptions: {
      onwarn(warning, defaultHandler) {
        if (
          warning.code === 'MIXED_EXPORTS' ||
          (warning.message &&
            warning.message.includes('is dynamically imported by') &&
            warning.message.includes('but also statically imported by'))
        ) {
          console.debug('[vite] suppressed:', warning.code, warning.message)
          return
        }
        defaultHandler(warning)
      },
      output: {
        manualChunks: {
          leaflet: ['leaflet'],
          'vue-draggable': ['vue-draggable-plus'],
        },
      },
    },
  },
  resolve: {
    alias: {
      '@': fileURLToPath(new URL('./src', import.meta.url)),
    },
  },
  server: {
    port,
    proxy: {
      '/api': {
        target: `http://localhost:${apiPort}`,
        changeOrigin: true,
      },
      '/ws': {
        target: `http://localhost:${apiPort}`,
        changeOrigin: true,
        ws: true,
      },
    },
  },
})
