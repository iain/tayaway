<script setup lang="ts">
import { computed, ref, useTemplateRef } from 'vue'
import {
  Combobox,
  ComboboxButton,
  ComboboxInput,
  ComboboxLabel,
  ComboboxOption,
  ComboboxOptions,
} from '@headlessui/vue'
import { CheckIcon, ChevronUpDownIcon } from '@heroicons/vue/16/solid'
import { deviceTimezone, formatZoneName } from '@/utils/timezone'

// A searchable timezone picker over the full IANA list. Used for the event
// zone (auto = derive from location), the user's display zone (auto = follow
// this device) and a workspace's home zone (always explicit).
//
// Search rather than a plain <select>: the raw list is ~450 entries sorted by
// region, so "Auckland" sits a long scroll below "Africa/Abidjan" and the
// alphabetical ordering is no help unless you already know the region. Typing
// any part of the name — city or region — narrows it in one keystroke.
//
// `autoLabel: null` drops the auto option for the zones that are always
// explicit — a workspace's own zone is what everything else falls back to,
// so there is nothing behind it to defer to.
const props = defineProps<{
  id: string
  label: string
  modelValue: string // "" = auto/default
  autoLabel: string | null
  disabled?: boolean
  effectiveZone?: string | null
  // For editors that already carry a heading of their own (a DefinitionRow's
  // <dt>), where a second visible copy of the label just repeats itself. The
  // label still exists for assistive tech.
  hideLabel?: boolean
}>()

const emit = defineEmits<{ 'update:modelValue': [value: string] }>()

interface ZoneOption {
  value: string
  city: string
  region: string
  offset: string
  hint?: string
}

function supportedZones(): string[] {
  const intl = Intl as unknown as {
    supportedValuesOf?: (key: 'timeZone') => string[]
  }
  return intl.supportedValuesOf ? intl.supportedValuesOf('timeZone') : []
}

// "GMT+2" / "GMT-5:30" for the zone as of now. Purely a reading aid, so a
// runtime that can't produce one just gets an empty string.
function offsetOf(zone: string): string {
  try {
    const parts = new Intl.DateTimeFormat('en-US', {
      timeZone: zone,
      timeZoneName: 'shortOffset',
    }).formatToParts(new Date())
    return parts.find((p) => p.type === 'timeZoneName')?.value ?? ''
  } catch {
    return ''
  }
}

// Built once: ~450 zones × an Intl formatter each is too much to redo on
// every keystroke, and the offsets only shift twice a year.
const allZones: ZoneOption[] = supportedZones().map((zone) => {
  const cut = zone.lastIndexOf('/')
  return {
    value: zone,
    city: (cut === -1 ? zone : zone.slice(cut + 1)).replace(/_/g, ' '),
    region: cut === -1 ? '' : zone.slice(0, cut).replace(/_/g, ' '),
    offset: offsetOf(zone),
  }
})

const AUTO_VALUE = ''
const MAX_VISIBLE = 60

const query = ref('')
const deviceZone = computed(() => deviceTimezone())

const autoOption = computed<ZoneOption | null>(() =>
  props.autoLabel === null
    ? null
    : {
        value: AUTO_VALUE,
        city: props.autoLabel,
        region: '',
        offset: '',
        hint: props.effectiveZone ?? deviceZone.value,
      }
)

// The device's own zone floats to the top of an unfiltered list — for most
// people it is the answer, and it saves them knowing which region owns their
// city.
const rankedZones = computed<ZoneOption[]>(() => {
  const device = allZones.find((z) => z.value === deviceZone.value)
  if (!device) return allZones
  return [
    { ...device, hint: 'Your device' },
    ...allZones.filter((z) => z.value !== device.value),
  ]
})

const filtered = computed<ZoneOption[]>(() => {
  const q = query.value.trim().toLowerCase()
  if (q === '') return rankedZones.value
  return allZones.filter((zone) =>
    `${zone.region} ${zone.city}`.toLowerCase().includes(q)
  )
})

const visible = computed(() => filtered.value.slice(0, MAX_VISIBLE))
const truncated = computed(() => filtered.value.length > MAX_VISIBLE)

const options = computed<ZoneOption[]>(() => {
  const auto = autoOption.value
  if (!auto) return visible.value
  // The auto option only survives a search when the query actually matches
  // its label — otherwise it would sit at the top of every result list.
  const q = query.value.trim().toLowerCase()
  const matches = q === '' || auto.city.toLowerCase().includes(q)
  return matches ? [auto, ...visible.value] : visible.value
})

function displayValue(value: unknown): string {
  const zone = String(value ?? '')
  if (zone === AUTO_VALUE) return props.autoLabel ?? ''
  return formatZoneName(zone)
}

function onSelect(value: unknown): void {
  query.value = ''
  emit('update:modelValue', String(value ?? ''))
}

// Let the opener put the cursor straight in the field — the picker is a
// search box, so an editor that opens without focus asks for an extra click
// before you can type.
const inputRef = useTemplateRef<{ el?: HTMLInputElement } & HTMLInputElement>(
  'inputRef'
)

function focus(): void {
  const el = inputRef.value
  const input =
    (el as { el?: HTMLInputElement })?.el ?? (el as HTMLInputElement)
  input?.focus?.()
  input?.select?.()
}

defineExpose({ focus })
</script>

<template>
  <div>
    <Combobox
      :model-value="modelValue"
      :disabled="disabled"
      as="div"
      class="relative"
      @update:model-value="onSelect"
    >
      <!-- ComboboxLabel rather than a plain <label>: HeadlessUI points the
           input's aria-labelledby at its own label (falling back to the
           icon-only toggle button, which has no text), so a raw label would
           leave the field with no accessible name. -->
      <ComboboxLabel
        :class="hideLabel ? 'sr-only' : 'text-label text-ink block'"
      >
        {{ label }}
      </ComboboxLabel>
      <div :class="['grid grid-cols-1', hideLabel ? '' : 'mt-2']">
        <ComboboxInput
          :id="id"
          ref="inputRef"
          class="bg-surface-sunken text-ink outline-line placeholder:text-ink-placeholder focus:outline-focus col-start-1 row-start-1 w-full rounded-md py-1.5 pr-8 pl-3 text-base outline-1 -outline-offset-1 focus:outline-2 focus:outline-offset-2 disabled:cursor-not-allowed disabled:opacity-50 sm:text-sm/6"
          :display-value="displayValue"
          placeholder="Search for a city or region"
          autocomplete="off"
          @change="query = ($event.target as HTMLInputElement).value"
        />
        <ComboboxButton
          class="col-start-1 row-start-1 flex items-center justify-self-end px-2 focus:outline-hidden"
        >
          <ChevronUpDownIcon class="text-ink-muted size-5" aria-hidden="true" />
        </ComboboxButton>
      </div>

      <ComboboxOptions
        class="bg-surface ring-line absolute z-10 mt-1 max-h-72 w-full overflow-auto rounded-md py-1 text-base shadow-lg ring-1 sm:text-sm"
      >
        <ComboboxOption
          v-for="option in options"
          :key="option.value || 'auto'"
          v-slot="{ active, selected }"
          :value="option.value"
          as="template"
        >
          <li
            :class="[
              'flex cursor-default items-center gap-2 px-3 py-2 select-none',
              active ? 'bg-amber-500 text-white dark:bg-amber-600' : 'text-ink',
            ]"
          >
            <span class="min-w-0 flex-1 truncate">
              {{ option.city }}
              <span
                v-if="option.region"
                :class="active ? 'text-white/70' : 'text-ink-muted'"
              >
                · {{ option.region }}
              </span>
              <span
                v-if="option.hint"
                :class="active ? 'text-white/70' : 'text-ink-muted'"
              >
                ({{ option.hint }})
              </span>
            </span>
            <span
              v-if="option.offset"
              :class="[
                'shrink-0 text-xs tabular-nums',
                active ? 'text-white/70' : 'text-ink-muted',
              ]"
            >
              {{ option.offset }}
            </span>
            <CheckIcon
              v-if="selected"
              class="size-4 shrink-0"
              aria-hidden="true"
            />
          </li>
        </ComboboxOption>

        <li
          v-if="options.length === 0"
          class="text-ink-muted px-3 py-2 text-sm"
        >
          No timezone matches “{{ query }}”.
        </li>
        <li v-else-if="truncated" class="text-ink-muted px-3 py-2 text-xs">
          More matches — keep typing to narrow the list.
        </li>
      </ComboboxOptions>
    </Combobox>

    <p
      v-if="modelValue === '' && effectiveZone"
      class="text-ink-muted text-meta mt-1"
    >
      Times shown in {{ formatZoneName(effectiveZone) }}
    </p>
  </div>
</template>
