import { defineConfig } from 'vite'
import vue from '@vitejs/plugin-vue'
import tailwindcss from '@tailwindcss/vite'
import { VitePWA } from 'vite-plugin-pwa'
import { compression } from 'vite-plugin-compression2'
import { fileURLToPath, URL } from 'node:url'

const port = parseInt(process.env.FRONTEND_PORT || '5173', 10)
const previewPort = parseInt(process.env.FRONTEND_PREVIEW_PORT || '5175', 10)
const apiPort = process.env.API_PORT || '9292'
// Undefined by default → vite's default `localhost` bind (IPv6 ::1 on macOS).
// Set FRONTEND_HOST=127.0.0.1 when fronting vite with a reverse proxy that
// dials 127.0.0.1 (e.g. pitchfork), which otherwise can't reach an IPv6-only bind.
const host = process.env.FRONTEND_HOST || undefined

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
    // Emit dist/assets/*.{br,gz} siblings alongside the originals so the
    // edge (Caddy `file_server { precompressed }`) can serve already-
    // compressed bytes without per-request CPU. The legacy nginx ignores
    // the siblings — they're just unused files on disk until cutover.
    // 1 KB threshold skips files where HTTP overhead would dominate.
    compression({ algorithms: ['brotliCompress', 'gzip'], threshold: 1024 }),
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
      // The push channel needs an active service worker even in dev,
      // because `pushManager.subscribe` waits on `serviceWorker.ready`.
      // Without this the Enable-push button hangs forever locally.
      devOptions: {
        enabled: true,
        type: 'module',
        navigateFallback: 'index.html',
      },
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
        codeSplitting: {
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
    host,
    port,
    proxy: apiProxy,
    fs: {
      // aube's isolated node_modules symlinks dependencies into the repo-root
      // `node_modules/.aube` store, which sits ABOVE this frontend/ project
      // root. Under pnpm, Vite auto-detected the workspace root via
      // pnpm-workspace.yaml and served from it; aube-workspace.yaml isn't a
      // marker Vite recognises, so without this the dev server 403s assets that
      // resolve through those symlinks — notably the bundled Inter web font,
      // whose absence silently falls back to a wider system sans and bloats the
      // design-system visual snapshot. Allow the repo root to restore access.
      allow: [fileURLToPath(new URL('..', import.meta.url))],
    },
  },
  preview: {
    port: previewPort,
    proxy: apiProxy,
  },
})
