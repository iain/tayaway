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
        icons: [{ src: '/icon.svg', sizes: 'any', type: 'image/svg+xml' }],
      },
      injectRegister: false,
      workbox: {
        globPatterns: ['**/*.{js,css,ico,png,svg,woff,woff2}'],
        runtimeCaching: [
          {
            urlPattern: ({ request }) => request.mode === 'navigate',
            handler: 'NetworkFirst',
            options: {
              cacheName: 'pages',
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
          return
        }
        defaultHandler(warning)
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
