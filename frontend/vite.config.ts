import { defineConfig } from 'vite'
import vue from '@vitejs/plugin-vue'
import tailwindcss from '@tailwindcss/vite'
import { VitePWA } from 'vite-plugin-pwa'
import { fileURLToPath, URL } from 'node:url'

const port = parseInt(process.env.FRONTEND_PORT || '5173', 10)
const previewPort = parseInt(process.env.FRONTEND_PREVIEW_PORT || '5175', 10)
const apiPort = process.env.API_PORT || '9292'

const apiProxy = {
  '/api': {
    target: `http://localhost:${apiPort}`,
    changeOrigin: true,
  },
  '/ws': {
    target: `http://localhost:${apiPort}`,
    changeOrigin: true,
    ws: true,
  },
}

// https://vite.dev/config/
export default defineConfig({
  plugins: [
    vue(),
    tailwindcss(),
    VitePWA({
      registerType: 'prompt',
      manifest: {
        id: '/',
        name: 'Tayaway',
        short_name: 'Tayaway',
        description: 'Collaborative event planning',
        start_url: '/',
        scope: '/',
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
        globPatterns: [
          '**/*.{js,css,html,ico,png,svg,webp,avif,woff,woff2,ttf,otf}',
        ],
        // Source maps are emitted next to the bundles but should never be
        // precached — they aren't useful offline and would just bloat the
        // precache. The glob above doesn't match `.map` today but this is
        // defensive against future glob changes.
        globIgnores: ['**/*.map'],
        navigateFallback: '/index.html',
        clientsClaim: true,
        // Imported into the generated SW so `push` and `notificationclick`
        // handlers ship alongside the workbox precache. Lives in `public/`
        // so it's served at the same origin as the SW.
        importScripts: ['/push-sw.js'],
      },
    }),
  ],
  build: {
    // Emit source maps next to the bundles so production errors stay
    // debuggable in browser devtools and stack traces map back to the
    // original TS/Vue source. Maps are fetched by the browser only when
    // devtools is open, so there's no user-facing bandwidth cost.
    sourcemap: true,
    rollupOptions: {
      onwarn(warning, defaultHandler) {
        if (
          warning.code === 'MIXED_EXPORTS' ||
          (warning.message &&
            warning.message.includes('is dynamically imported by') &&
            warning.message.includes('but also statically imported by'))
        ) {
          if (process.env.NODE_ENV === 'development') {
            console.debug('[vite] suppressed:', warning.code, warning.message)
          }
          return
        }
        defaultHandler(warning)
      },
      output: {
        advancedChunks: {
          groups: [
            { name: 'leaflet', test: /node_modules\/leaflet\// },
            {
              name: 'vue-draggable',
              test: /node_modules\/vue-draggable-plus\//,
            },
          ],
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
    proxy: apiProxy,
    forwardConsole: true,
  },
  preview: {
    port: previewPort,
    proxy: apiProxy,
  },
})
