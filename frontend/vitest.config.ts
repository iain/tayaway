import { defineConfig } from 'vitest/config'
import vue from '@vitejs/plugin-vue'
import { fileURLToPath, URL } from 'node:url'

export default defineConfig({
  plugins: [vue()],
  test: {
    environment: 'jsdom',
    include: ['src/**/*.spec.ts'],
    setupFiles: ['src/tests/setup.ts'],
    tags: [
      {
        name: 'known-gap',
        description:
          'A Sync Engine v2 guarantee that does not hold yet: the test must fail, and fails the run once it passes (doc/sync/roadmap.md)',
        fails: true,
      },
    ],
  },
  resolve: {
    alias: {
      '@': fileURLToPath(new URL('./src', import.meta.url)),
    },
  },
})
