<script setup lang="ts">
// Blocking full-screen overlay shown when the server rejected this client's
// protocol version (see api/updateRequired.ts). The forced service worker
// update normally reloads within seconds; the button is the manual escape
// hatch if that machinery stalls (SW unsupported, update fetch failing).
function reloadNow(): void {
  window.location.reload()
}
</script>

<template>
  <div
    class="bg-surface-page fixed inset-0 z-50 flex flex-col items-center justify-center gap-3 p-6 text-center"
    role="alertdialog"
    aria-labelledby="update-required-title"
  >
    <div
      class="inline-block h-10 w-10 animate-spin rounded-full border-4 border-amber-600 border-t-transparent"
    />
    <h1 id="update-required-title" class="text-ink mt-2 text-lg font-semibold">
      Update required
    </h1>
    <p class="text-ink-secondary max-w-sm text-sm">
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
