import { Controller } from '@hotwired/stimulus'
import { decodeGrid, downsample, analyzeDrainage, RainSimulation } from '../utils/map_relief_hydro'

// La vue 3D du relief et du ruissellement (`/map/relief`).
//
// Le MNT arrive en binaire (`grid.bin`, voir `Maps::Terrain`), la scène three.js
// se charge en `import()` dynamique, puis tout se calcule dans le navigateur :
// axes d'écoulement et cuvettes une fois pour toutes (~0,3 s), la pluie pas à
// pas tant qu'elle tourne. Rien ne repart vers le serveur.
//
// La simulation tourne sur une grille de 2 m (quatre fois moins de mailles que
// le relief à 1 m) : une averse d'une heure s'y joue en une quinzaine de
// secondes, et la lame d'eau reste fine à l'échelle d'un talweg.

const SIM_FACTOR = 2
const SIM_DT = 0.5
// Seuil des axes d'écoulement : une maille qui draine au moins 0,2 ha.
const AXIS_THRESHOLD = 2000
const FRAME_BUDGET_MS = 11

const HYPSOMETRY = [
  [0, [47, 107, 58]],
  [0.25, [127, 174, 90]],
  [0.5, [216, 199, 122]],
  [0.75, [176, 125, 79]],
  [1, [241, 238, 230]],
]

const LAYER_COLORS = { venues: '#f59e0b', management: '#fafaf9', welcome: '#a3e635' }

export default class extends Controller {
  static targets = [
    'viewport', 'loading', 'panel', 'panelBody', 'exaggeration', 'exaggerationLabel',
    'playButton', 'playLabel', 'clock', 'rainState', 'stats', 'probe',
  ]

  static values = {
    gridUrl: String,
    textureUrl: String,
    meta: Object,
    featuresUrl: String,
    featureLayers: Array,
  }

  async connect() {
    this.settings = {
      base: 'ortho', contour: 5, axes: true, hollows: true, features: true, particles: true,
      intensity: 30, duration: 60, infiltration: 10, speed: 4,
    }
    this.playing = false
    this.features = []
    try {
      await this.load()
    } catch (error) {
      console.error(error)
      this.setLoading(`Le relief n'a pas pu s'afficher : ${error.message}`, true)
    }
  }

  disconnect() {
    this.disposed = true
    this.scene?.dispose()
  }

  async load() {
    this.setLoading('Chargement du relief…')
    const [response, { ReliefScene }] = await Promise.all([
      fetch(this.gridUrlValue, { credentials: 'same-origin' }),
      import('../utils/map_relief_scene'),
    ])
    if (!response.ok) throw new Error(`grille indisponible (${response.status})`)
    const meta = this.metaValue
    const full = decodeGrid(await response.arrayBuffer(), meta)
    if (this.disposed) return

    // Sur un petit écran, le maillage passe à 2 m : 190 000 sommets au lieu de
    // 750 000, la différence ne se voit pas sur un téléphone.
    const meshFactor = window.matchMedia('(max-width: 767px)').matches ? 2 : 1
    const mesh = downsample(full, meta.cols, meta.rows, meshFactor)
    let zMin = Infinity
    let zMax = -Infinity
    for (const z of full) { if (z < zMin) zMin = z; if (z > zMax) zMax = z }
    this.full = { heights: full, cols: meta.cols, rows: meta.rows }
    this.meshFactor = meshFactor
    this.zRange = [zMin, zMax]
    this.scene = new ReliefScene(this.viewportTarget, {
      heights: mesh.heights, cols: mesh.cols, rows: mesh.rows, cellSize: meta.cell_size_m * meshFactor,
      zBase: Math.floor(zMin) - 1, zMid: (zMin + zMax) / 2,
    })
    this.scene.setExaggeration(Number(this.exaggerationTarget.value))
    this.scene.setContourInterval(this.settings.contour)
    this.scene.onFrame = () => this.tick()
    this.bindPicking()

    this.setLoading('Calcul des axes d\'écoulement…')
    await nextPaint()
    this.drainage = analyzeDrainage(full, meta.cols, meta.rows, meta.cell_size_m)
    this.hypsometryTexture = this.scene.canvasTexture(this.hypsometryCanvas())
    await this.applyBase()
    this.drawOverlay()
    this.setLoading(null)
    this.loadFeatures()
  }

  // ---- Réglages de la vue ---------------------------------------------------

  async setBase(event) {
    this.settings.base = event.params.value
    this.markChoice(event)
    await this.applyBase()
  }

  async applyBase() {
    if (this.settings.base === 'ortho' && this.hasTextureUrlValue && this.textureUrlValue) {
      this.orthoTexture ||= await this.scene.loadImageTexture(this.textureUrlValue).catch(() => null)
      if (this.orthoTexture) return this.scene.setBaseTexture(this.orthoTexture)
    }
    this.scene.setBaseTexture(this.hypsometryTexture)
  }

  setExaggeration() {
    const value = Number(this.exaggerationTarget.value)
    this.exaggerationLabelTarget.textContent = `×${formatNumber(value, 1)}`
    this.scene?.setExaggeration(value)
  }

  setContour(event) {
    this.settings.contour = Number(event.params.value)
    this.markChoice(event)
    this.scene?.setContourInterval(this.settings.contour)
  }

  toggle(event) {
    const key = event.params.key
    this.settings[key] = event.target.checked
    if (key === 'particles') {
      if (this.scene) this.scene.particlesOn = event.target.checked
      return
    }
    this.drawOverlay()
  }

  resetView() {
    this.scene?.resetView()
  }

  togglePanel() {
    const hidden = this.panelBodyTarget.classList.toggle('hidden')
    this.panelTarget.querySelector('[aria-expanded]')?.setAttribute('aria-expanded', String(!hidden))
  }

  // ---- La pluie -------------------------------------------------------------

  setRain(event) {
    this.settings[event.params.key] = Number(event.params.value)
    this.markChoice(event)
    this.simulation?.setOptions(this.simOptions())
    this.renderStats()
  }

  simOptions() {
    const { intensity, duration, infiltration } = this.settings
    return { intensity, duration, infiltration }
  }

  togglePlay() {
    if (!this.scene) return
    if (!this.simulation) {
      const grid = downsample(this.full.heights, this.full.cols, this.full.rows, SIM_FACTOR)
      this.simulation = new RainSimulation(grid.heights, grid.cols, grid.rows,
                                           this.metaValue.cell_size_m * SIM_FACTOR, this.simOptions())
    }
    this.playing = !this.playing
    this.playLabelTarget.textContent = this.playing ? 'Pause' : (this.simulation.time > 0 ? 'Reprendre' : 'Faire pleuvoir')
    this.playButtonTarget.setAttribute('aria-pressed', String(this.playing))
  }

  resetRain() {
    this.playing = false
    this.simulation?.reset()
    this.scene?.clearWater()
    this.playLabelTarget.textContent = 'Faire pleuvoir'
    this.playButtonTarget.setAttribute('aria-pressed', 'false')
    this.renderStats()
  }

  // Appelé à chaque image par la scène : autant de pas que le budget en permet,
  // plafonné par la vitesse choisie.
  tick() {
    const sim = this.simulation
    if (!sim || !this.playing) return
    const start = performance.now()
    const steps = this.settings.speed * 2
    for (let s = 0; s < steps; s++) {
      sim.step(SIM_DT)
      if (performance.now() - start > FRAME_BUDGET_MS) break
    }
    this.scene.updateWater(sim)
    this.scene.updateParticles(sim)
    const now = performance.now()
    if (!this.lastStats || now - this.lastStats > 250) {
      this.lastStats = now
      this.renderStats()
    }
  }

  renderStats() {
    const sim = this.simulation
    const time = sim ? sim.time : 0
    this.clockTarget.textContent = formatDuration(time)
    if (!sim || time === 0) {
      this.rainStateTarget.textContent = `${this.settings.intensity} mm/h pendant ${formatMinutes(this.settings.duration)}`
      this.statsTarget.innerHTML = ''
      return
    }
    this.rainStateTarget.textContent = sim.raining ? `Il pleut : ${this.settings.intensity} mm/h` : 'La pluie a cessé, l\'eau s\'écoule'
    let deepest = 0
    for (const d of sim.depth) if (d > deepest) deepest = d
    const rows = [
      ['Pluie tombée', sim.rained],
      ['Bue par le sol', sim.infiltrated],
      ['Partie hors de la zone', sim.outflow],
      ['Encore sur le terrain', sim.stored()],
    ]
    this.statsTarget.innerHTML = rows.map(([label, volume]) => (
      `<div class="flex justify-between gap-2"><dt class="text-stone-500">${label}</dt><dd class="tabular-nums text-stone-800">${formatVolume(volume)}</dd></div>`
    )).join('') + `<div class="flex justify-between gap-2"><dt class="text-stone-500">Lame d'eau la plus profonde</dt><dd class="tabular-nums text-stone-800">${formatDepth(deepest)}</dd></div>`
  }

  // ---- Surimpressions -------------------------------------------------------

  // Axes d'écoulement et cuvettes à la résolution du MNT (1 px = 1 m), puis les
  // objets de la carte en vectoriel par-dessus, à 2 px par mètre.
  drawOverlay() {
    if (!this.scene || !this.drainage) return
    const { cols, rows } = this.full
    const canvas = this.scene.overlayCanvas
    const context = canvas.getContext('2d')
    context.clearRect(0, 0, canvas.width, canvas.height)

    const raster = document.createElement('canvas')
    raster.width = cols
    raster.height = rows
    const image = raster.getContext('2d').createImageData(cols, rows)
    const data = image.data
    const { accumulation, depression } = this.drainage
    let accMax = AXIS_THRESHOLD
    for (const a of accumulation) if (a > accMax) accMax = a
    const logMin = Math.log10(AXIS_THRESHOLD)
    const logSpan = Math.max(0.1, Math.log10(accMax) - logMin)
    for (let i = 0; i < accumulation.length; i++) {
      const o = i * 4
      if (this.settings.axes && accumulation[i] >= AXIS_THRESHOLD) {
        const t = Math.min(1, (Math.log10(accumulation[i]) - logMin) / logSpan)
        data[o] = 125 - 96 * t
        data[o + 1] = 211 - 133 * t
        data[o + 2] = 252 - 36 * t
        data[o + 3] = 170 + 85 * t
      } else if (this.settings.hollows && depression[i] > 0.05) {
        const t = Math.min(1, depression[i] / 1.5)
        data[o] = 14
        data[o + 1] = 165
        data[o + 2] = 233
        data[o + 3] = 70 + 110 * t
      }
    }
    raster.getContext('2d').putImageData(image, 0, 0)
    context.imageSmoothingEnabled = false
    context.drawImage(raster, 0, 0, canvas.width, canvas.height)

    if (this.settings.features) this.drawFeatures(context, canvas)
    this.scene.refreshOverlay()
  }

  async loadFeatures() {
    const layers = this.featureLayersValue
    const results = await Promise.all(layers.map(async (layer) => {
      try {
        const url = `${this.featuresUrlValue}?layer_id=${encodeURIComponent(layer.id)}`
        const response = await fetch(url, { headers: { Accept: 'application/json' }, credentials: 'same-origin' })
        if (!response.ok) return []
        const collection = await response.json()
        return (collection.features || []).map((feature) => ({ feature, layer }))
      } catch {
        return []
      }
    }))
    if (this.disposed) return
    this.features = results.flat()
    this.drawOverlay()
  }

  drawFeatures(context, canvas) {
    const meta = this.metaValue
    const sx = canvas.width / (meta.cols - 1)
    const sy = canvas.height / (meta.rows - 1)
    const project = ([lng, lat]) => {
      const [x, y] = toMercator(lat, lng)
      return [((x - meta.west) / meta.step) * sx, ((meta.north - y) / meta.step) * sy]
    }
    context.lineJoin = 'round'
    context.lineCap = 'round'
    for (const { feature, layer } of this.features) {
      const geometry = feature.geometry
      if (!geometry?.coordinates) continue
      const color = feature.properties?.color || LAYER_COLORS[layer.kind] || '#fafaf9'
      context.strokeStyle = color
      context.fillStyle = color
      const polygons = geometry.type === 'Polygon' ? [geometry.coordinates]
        : geometry.type === 'MultiPolygon' ? geometry.coordinates : []
      for (const polygon of polygons) {
        context.beginPath()
        for (const ring of polygon) {
          ring.forEach((point, k) => {
            const [px, py] = project(point)
            if (k === 0) context.moveTo(px, py)
            else context.lineTo(px, py)
          })
          context.closePath()
        }
        context.globalAlpha = 0.14
        context.fill('evenodd')
        context.globalAlpha = 0.95
        context.lineWidth = 2.5
        context.stroke()
      }
      const lines = geometry.type === 'LineString' ? [geometry.coordinates]
        : geometry.type === 'MultiLineString' ? geometry.coordinates : []
      for (const line of lines) {
        context.beginPath()
        line.forEach((point, k) => {
          const [px, py] = project(point)
          if (k === 0) context.moveTo(px, py)
          else context.lineTo(px, py)
        })
        context.globalAlpha = 0.95
        context.lineWidth = 2.5
        context.stroke()
      }
      if (geometry.type === 'Point') {
        const [px, py] = project(geometry.coordinates)
        context.globalAlpha = 0.95
        context.beginPath()
        context.arc(px, py, 3, 0, Math.PI * 2)
        context.fill()
      }
    }
    context.globalAlpha = 1
  }

  hypsometryCanvas() {
    const { heights, cols, rows } = this.full
    const [zMin, zMax] = this.zRange
    const canvas = document.createElement('canvas')
    canvas.width = cols
    canvas.height = rows
    const context = canvas.getContext('2d')
    const image = context.createImageData(cols, rows)
    const span = Math.max(1, zMax - zMin)
    for (let i = 0; i < heights.length; i++) {
      const [r, g, b] = ramp((heights[i] - zMin) / span)
      image.data[i * 4] = r
      image.data[i * 4 + 1] = g
      image.data[i * 4 + 2] = b
      image.data[i * 4 + 3] = 255
    }
    context.putImageData(image, 0, 0)
    return canvas
  }

  // ---- La sonde : ce qu'on sait du point touché ------------------------------

  bindPicking() {
    const element = this.scene.renderer.domElement
    element.addEventListener('pointerdown', (event) => { this.pointerStart = [event.clientX, event.clientY] })
    element.addEventListener('pointerup', (event) => {
      const start = this.pointerStart
      if (!start || Math.hypot(event.clientX - start[0], event.clientY - start[1]) > 5) return
      this.probe(event)
    })
  }

  probe(event) {
    const hit = this.scene.pick(event)
    if (!hit) {
      this.probeTarget.classList.add('hidden')
      return
    }
    const col = Math.min(this.full.cols - 1, hit.col * this.meshFactor)
    const row = Math.min(this.full.rows - 1, hit.row * this.meshFactor)
    const i = row * this.full.cols + col
    const lines = [`<p class="font-semibold text-stone-800">Altitude ${formatNumber(this.full.heights[i], 1)} m</p>`]
    const drained = this.drainage?.accumulation[i] || 0
    lines.push(`<p>Surface drainée en amont : <span class="tabular-nums">${formatArea(drained)}</span></p>`)
    const hollow = this.drainage?.depression[i] || 0
    if (hollow > 0.05) lines.push(`<p>Dans une cuvette : l'eau peut y monter de ${formatDepth(hollow)}</p>`)
    const sim = this.simulation
    if (sim && sim.time > 0) {
      const sc = Math.min(sim.cols - 1, Math.floor(col / SIM_FACTOR))
      const sr = Math.min(sim.rows - 1, Math.floor(row / SIM_FACTOR))
      const k = sr * sim.cols + sc
      const speed = Math.hypot(sim.velX[k], sim.velY[k])
      lines.push(`<p>Eau : ${formatDepth(sim.depth[k])}${speed > 0.01 ? `, ${formatNumber(speed, 2)} m/s` : ''}</p>`)
    }
    this.probeTarget.innerHTML = lines.join('')
    this.probeTarget.classList.remove('hidden')
  }

  // ---- Petits outils --------------------------------------------------------

  markChoice(event) {
    const group = event.currentTarget.closest('[data-choice-group]')
    group?.querySelectorAll('[aria-pressed]').forEach((button) => {
      button.setAttribute('aria-pressed', String(button === event.currentTarget))
    })
  }

  setLoading(message, isError = false) {
    if (!this.hasLoadingTarget) return
    this.loadingTarget.classList.toggle('hidden', !message)
    this.loadingTarget.textContent = message || ''
    this.loadingTarget.classList.toggle('text-red-700', isError)
  }
}

function nextPaint() {
  return new Promise((resolve) => setTimeout(resolve, 30))
}

function toMercator(lat, lng) {
  const radius = 6378137
  return [radius * (lng * Math.PI) / 180, radius * Math.log(Math.tan(Math.PI / 4 + (lat * Math.PI) / 360))]
}

function ramp(t) {
  const x = Math.min(1, Math.max(0, t))
  for (let k = 1; k < HYPSOMETRY.length; k++) {
    const [t1, c1] = HYPSOMETRY[k]
    const [t0, c0] = HYPSOMETRY[k - 1]
    if (x <= t1) {
      const f = (x - t0) / (t1 - t0)
      return c0.map((v, j) => Math.round(v + (c1[j] - v) * f))
    }
  }
  return HYPSOMETRY[HYPSOMETRY.length - 1][1]
}

function formatNumber(value, digits = 0) {
  return Number(value).toLocaleString('fr-BE', { minimumFractionDigits: digits, maximumFractionDigits: digits })
}

function formatVolume(m3) {
  if (m3 < 10) return `${formatNumber(m3, 1)} m³`
  return `${formatNumber(m3)} m³`
}

function formatDepth(meters) {
  if (meters < 0.01) return `${formatNumber(meters * 1000)} mm`
  if (meters < 1) return `${formatNumber(meters * 100)} cm`
  return `${formatNumber(meters, 2)} m`
}

function formatArea(m2) {
  if (m2 < 10000) return `${formatNumber(m2)} m²`
  return `${formatNumber(m2 / 10000, 1)} ha`
}

function formatDuration(seconds) {
  const total = Math.floor(seconds)
  const h = Math.floor(total / 3600)
  const m = Math.floor((total % 3600) / 60)
  const s = total % 60
  return h > 0 ? `${h} h ${String(m).padStart(2, '0')}` : `${m} min ${String(s).padStart(2, '0')}`
}

function formatMinutes(minutes) {
  return minutes >= 60 ? `${formatNumber(minutes / 60)} h` : `${minutes} min`
}
