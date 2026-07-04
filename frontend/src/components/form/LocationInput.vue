<script setup lang="ts">
import { ref, watch, onBeforeUnmount, useTemplateRef } from 'vue'
import { XMarkIcon, MapPinIcon } from '@heroicons/vue/24/outline'

const props = defineProps<{
  modelValue: string
  latitude: number | null
  longitude: number | null
  disabled?: boolean
  label?: string
  ariaLabel?: string
  maxlength?: number
}>()

const emit = defineEmits<{
  'update:modelValue': [value: string]
  'update:latitude': [value: number | null]
  'update:longitude': [value: number | null]
  select: [
    location: { locationName: string; latitude: number; longitude: number },
  ]
}>()

interface PhotonFeature {
  geometry: { coordinates: [number, number] }
  properties: {
    name?: string
    street?: string
    housenumber?: string
    city?: string
    state?: string
    country?: string
    postcode?: string
  }
}

const query = ref(props.modelValue)
const suggestions = ref<PhotonFeature[]>([])
const showDropdown = ref(false)
const activeIndex = ref(-1)
let debounceTimer: ReturnType<typeof setTimeout> | null = null
let abortController: AbortController | null = null

watch(
  () => props.modelValue,
  (v) => {
    query.value = v
  }
)

function formatAddress(f: PhotonFeature): string {
  const p = f.properties
  const parts: string[] = []
  if (p.name) parts.push(p.name)
  if (p.street) {
    const street = p.housenumber ? `${p.street} ${p.housenumber}` : p.street
    if (street !== p.name) parts.push(street)
  }
  if (p.city && p.city !== p.name) parts.push(p.city)
  if (p.country) parts.push(p.country)
  return parts.join(', ')
}

function handleInput(e: Event): void {
  const value = (e.target as HTMLInputElement).value
  query.value = value

  if (debounceTimer) clearTimeout(debounceTimer)

  if (!value.trim()) {
    suggestions.value = []
    showDropdown.value = false
    return
  }

  activeIndex.value = -1
  debounceTimer = setTimeout(() => {
    fetchSuggestions(value.trim())
  }, 300)
}

async function fetchSuggestions(q: string): Promise<void> {
  if (abortController) abortController.abort()
  abortController = new AbortController()

  try {
    const timeoutSignal = AbortSignal.timeout(10_000)
    const res = await fetch(
      `https://photon.komoot.io/api/?q=${encodeURIComponent(q)}&limit=5`,
      { signal: AbortSignal.any([abortController.signal, timeoutSignal]) }
    )
    const data = await res.json()
    suggestions.value = data.features ?? []
    showDropdown.value = suggestions.value.length > 0
  } catch {
    // aborted or network error
  }
}

function handleKeydown(e: KeyboardEvent): void {
  if (!showDropdown.value || suggestions.value.length === 0) return

  if (e.key === 'ArrowDown') {
    e.preventDefault()
    activeIndex.value = (activeIndex.value + 1) % suggestions.value.length
  } else if (e.key === 'ArrowUp') {
    e.preventDefault()
    activeIndex.value =
      activeIndex.value <= 0
        ? suggestions.value.length - 1
        : activeIndex.value - 1
  } else if (e.key === 'Enter') {
    e.preventDefault()
    const active = suggestions.value[activeIndex.value]
    if (active) {
      selectSuggestion(active)
    }
  } else if (e.key === 'Escape') {
    showDropdown.value = false
    activeIndex.value = -1
  }
}

function selectSuggestion(feature: PhotonFeature): void {
  const name = formatAddress(feature)
  const [lng, lat] = feature.geometry.coordinates
  query.value = name
  suggestions.value = []
  showDropdown.value = false
  emit('update:modelValue', name)
  emit('update:latitude', lat)
  emit('update:longitude', lng)
  emit('select', { locationName: name, latitude: lat, longitude: lng })
}

function clear(): void {
  query.value = ''
  suggestions.value = []
  showDropdown.value = false
  emit('update:modelValue', '')
  emit('update:latitude', null)
  emit('update:longitude', null)
}

function handleBlur(): void {
  // Delay to allow click on suggestion
  setTimeout(() => {
    showDropdown.value = false
  }, 200)
}

onBeforeUnmount(() => {
  if (debounceTimer) clearTimeout(debounceTimer)
  if (abortController) abortController.abort()
})

const inputEl = useTemplateRef<HTMLInputElement>('inputEl')

defineExpose({
  focus: () => inputEl.value?.focus(),
})
</script>

<template>
  <div class="relative">
    <label v-if="label" class="text-label text-ink block">
      {{ label }}
    </label>
    <div class="relative mt-2">
      <div
        class="pointer-events-none absolute inset-y-0 left-0 flex items-center pl-3"
      >
        <MapPinIcon class="text-ink-muted size-4" />
      </div>
      <input
        ref="inputEl"
        type="text"
        :value="query"
        :aria-label="!label ? ariaLabel : undefined"
        :disabled="disabled"
        :maxlength="maxlength"
        placeholder="Search for a location..."
        autocomplete="off"
        class="bg-surface-sunken text-ink placeholder:text-ink-placeholder outline-line focus:outline-focus block w-full rounded-md py-1.5 pr-9 pl-9 text-base outline-1 -outline-offset-1 focus:outline-2 focus:outline-offset-2 disabled:cursor-not-allowed disabled:opacity-50 sm:text-sm/6"
        @input="handleInput"
        @keydown="handleKeydown"
        @focus="showDropdown = suggestions.length > 0"
        @blur="handleBlur"
      />
      <button
        v-if="query"
        type="button"
        class="text-ink-muted hover:text-ink absolute inset-y-0 right-0 flex items-center pr-3"
        @click="clear"
      >
        <XMarkIcon class="size-4" />
      </button>
    </div>
    <ul
      v-if="showDropdown"
      role="listbox"
      class="bg-surface ring-ring-hairline absolute z-10 mt-1 max-h-60 w-full overflow-auto rounded-md py-1 text-base shadow-lg ring-1 sm:text-sm"
    >
      <li
        v-for="(feature, i) in suggestions"
        :key="i"
        role="option"
        class="text-ink cursor-pointer px-3 py-2 transition-colors"
        :class="
          i === activeIndex
            ? 'bg-rose-50 dark:bg-rose-950/40'
            : 'hover:bg-rose-50 dark:hover:bg-rose-950/40'
        "
        @mousedown.prevent="selectSuggestion(feature)"
        @mouseenter="activeIndex = i"
      >
        {{ formatAddress(feature) }}
      </li>
    </ul>
  </div>
</template>
