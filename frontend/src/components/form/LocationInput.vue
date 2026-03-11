<script setup lang="ts">
import { ref, watch, onBeforeUnmount } from 'vue'
import { XMarkIcon, MapPinIcon } from '@heroicons/vue/24/outline'

const props = defineProps<{
  modelValue: string
  latitude: number | null
  longitude: number | null
  disabled?: boolean
  label?: string
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
    const res = await fetch(
      `https://photon.komoot.io/api/?q=${encodeURIComponent(q)}&limit=5`,
      { signal: abortController.signal }
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
</script>

<template>
  <div class="relative">
    <label
      v-if="label"
      class="block text-sm/6 font-medium text-gray-900 dark:text-white"
    >
      {{ label }}
    </label>
    <div class="relative mt-2">
      <div
        class="pointer-events-none absolute inset-y-0 left-0 flex items-center pl-3"
      >
        <MapPinIcon class="size-4 text-gray-400 dark:text-stone-500" />
      </div>
      <input
        ref="inputEl"
        type="text"
        :value="query"
        :disabled="disabled"
        placeholder="Search for a location..."
        autocomplete="off"
        class="block w-full rounded-md bg-gray-100 py-1.5 pr-9 pl-9 text-base text-gray-900 outline-1 -outline-offset-1 outline-gray-300 placeholder:text-gray-400 focus:outline-2 focus:-outline-offset-2 focus:outline-rose-500 disabled:cursor-not-allowed disabled:opacity-50 sm:text-sm/6 dark:bg-white/5 dark:text-white dark:outline-white/10 dark:placeholder:text-stone-500"
        @input="handleInput"
        @keydown="handleKeydown"
        @focus="showDropdown = suggestions.length > 0"
        @blur="handleBlur"
      />
      <button
        v-if="query"
        type="button"
        class="absolute inset-y-0 right-0 flex items-center pr-3 text-gray-400 hover:text-gray-600 dark:text-stone-500 dark:hover:text-stone-300"
        @click="clear"
      >
        <XMarkIcon class="size-4" />
      </button>
    </div>
    <ul
      v-if="showDropdown"
      role="listbox"
      class="absolute z-10 mt-1 max-h-60 w-full overflow-auto rounded-md bg-white py-1 text-base shadow-lg ring-1 ring-black/5 sm:text-sm dark:bg-stone-800 dark:ring-white/10"
    >
      <li
        v-for="(feature, i) in suggestions"
        :key="i"
        role="option"
        class="cursor-pointer px-3 py-2 text-gray-900 transition-colors dark:text-white"
        :class="
          i === activeIndex
            ? 'bg-rose-50 dark:bg-stone-700'
            : 'hover:bg-rose-50 dark:hover:bg-stone-700'
        "
        @mousedown.prevent="selectSuggestion(feature)"
        @mouseenter="activeIndex = i"
      >
        {{ formatAddress(feature) }}
      </li>
    </ul>
  </div>
</template>
