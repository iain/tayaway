<script setup lang="ts">
import { ref, onMounted, onBeforeUnmount, watch } from 'vue'
import L from 'leaflet'

const props = defineProps<{
  latitude: number
  longitude: number
}>()

const mapContainer = ref<HTMLDivElement>()
let map: L.Map | null = null
let marker: L.Marker | null = null

// Fix default marker icon paths (Leaflet bundles them but Vite doesn't resolve them)
const defaultIcon = L.icon({
  iconUrl: 'https://unpkg.com/leaflet@1.9.4/dist/images/marker-icon.png',
  iconRetinaUrl:
    'https://unpkg.com/leaflet@1.9.4/dist/images/marker-icon-2x.png',
  shadowUrl: 'https://unpkg.com/leaflet@1.9.4/dist/images/marker-shadow.png',
  iconSize: [25, 41],
  iconAnchor: [12, 41],
  popupAnchor: [1, -34],
  shadowSize: [41, 41],
})

function initMap(): void {
  if (!mapContainer.value) return

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

onMounted(() => {
  initMap()
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
