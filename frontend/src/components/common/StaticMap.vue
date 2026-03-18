<script setup lang="ts">
import { ref, onMounted, onBeforeUnmount, watch, shallowRef } from 'vue'
import type L from 'leaflet'
import markerIcon from 'leaflet/dist/images/marker-icon.png'
import markerIcon2x from 'leaflet/dist/images/marker-icon-2x.png'
import markerShadow from 'leaflet/dist/images/marker-shadow.png'

const props = defineProps<{
  latitude: number
  longitude: number
}>()

const mapContainer = ref<HTMLDivElement>()
const loaded = ref(false)
const leafletModule = shallowRef<typeof import('leaflet') | null>(null)
let map: L.Map | null = null
let marker: L.Marker | null = null

async function loadLeaflet(): Promise<typeof import('leaflet')> {
  if (leafletModule.value) return leafletModule.value
  const [mod] = await Promise.all([
    import('leaflet'),
    import('leaflet/dist/leaflet.css'),
  ])
  leafletModule.value = mod
  return mod
}

function initMap(L: typeof import('leaflet')): void {
  if (!mapContainer.value) return

  const defaultIcon = L.icon({
    iconUrl: markerIcon,
    iconRetinaUrl: markerIcon2x,
    shadowUrl: markerShadow,
    iconSize: [25, 41],
    iconAnchor: [12, 41],
    popupAnchor: [1, -34],
    shadowSize: [41, 41],
  })

  map = L.map(mapContainer.value, {
    zoomControl: false,
    dragging: false,
    scrollWheelZoom: false,
    doubleClickZoom: false,
    boxZoom: false,
    keyboard: false,
    touchZoom: false,
    attributionControl: false,
  })

  L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png').addTo(map)

  const latLng: L.LatLngExpression = [props.latitude, props.longitude]
  map.setView(latLng, 15)
  marker = L.marker(latLng, { icon: defaultIcon }).addTo(map)
  loaded.value = true
}

watch(
  () => [props.latitude, props.longitude] as const,
  ([lat, lng]) => {
    if (map && marker) {
      const latLng: L.LatLngExpression = [lat, lng]
      map.setView(latLng, 15)
      marker.setLatLng(latLng)
    }
  }
)

onMounted(async () => {
  const L = await loadLeaflet()
  initMap(L)
})

onBeforeUnmount(() => {
  if (map) {
    map.remove()
    map = null
    marker = null
  }
})
</script>

<template>
  <div ref="mapContainer" class="h-48 w-full rounded-lg" />
</template>
