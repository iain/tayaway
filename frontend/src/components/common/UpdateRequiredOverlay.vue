<script setup lang="ts">
import { onMounted, useTemplateRef } from 'vue'

// Blocking full-screen overlay shown when the server rejected this client's
// protocol version (see api/updateRequired.ts). The forced service worker
// update normally reloads within seconds; the button is the manual escape
// hatch if that machinery stalls (SW unsupported, update fetch failing).
const dialog = useTemplateRef('dialog')

// Move focus into the dialog so screen readers announce it and keyboard
// focus doesn't linger on the (visually covered) app behind it. No focus
// trap — the reload lands within seconds and the only control is inside.
onMounted(() => dialog.value?.focus())

function reloadNow(): void {
  window.location.reload()
}
</script>

<template>
  <div
    ref="dialog"
    class="bg-surface-page fixed inset-0 z-50 flex flex-col items-center justify-center gap-3 p-6 text-center focus:outline-none"
    role="alertdialog"
    aria-modal="true"
    aria-labelledby="update-required-title"
    aria-describedby="update-required-description"
    tabindex="-1"
  >
    <div
      class="inline-block h-10 w-10 animate-spin rounded-full border-4 border-amber-600 border-t-transparent"
    />
    <h1 id="update-required-title" class="text-ink mt-2 text-lg font-semibold">
      Update required
    </h1>
    <p
      id="update-required-description"
      class="text-ink-secondary max-w-sm text-sm"
    >
      This version of Tayaway is no longer supported by the server. Updating to
      the latest version…
    </p>
    <button
      type="button"
      class="text-ink-secondary mt-4 text-sm underline underline-offset-2 hover:text-amber-600"
      @click="reloadNow"
    >
      Taking too long? Reload now
    </button>
  </div>
</template>
