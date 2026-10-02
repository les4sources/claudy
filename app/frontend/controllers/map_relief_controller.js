import { Controller } from '@hotwired/stimulus'
import { decodeGrid, downsample, analyzeDrainage, RainSimulation } from '../utils/map_relief_hydro'
import { sunPosition, shadowMask, sunHours } from '../utils/map_relief_sun'
import {
  slopeAspect, spreadAccumulation, wetnessIndex, frostRisk, boxBlur, towards, wetnessClass, frostClass,
} from '../utils/map_relief_station'
import { traceContour, applyDesigns, downsampleDesigned, HEDGE_SOIL } from '../utils/map_relief_design'

// La vue 3D du relief et du ruissellement (`/map/relief`).
//
// Le MNT arrive en binaire (`grid.bin`, voir `Maps::Terrain`), la scène three.js
// se charge en `import()` dynamique, puis tout se calcule dans le navigateur :
// axes d'écoulement et cuvettes une fois pour toutes (~0,3 s), la pluie pas à
// pas tant qu'elle tourne. Rien ne repart vers le serveur.
//
// Le soleil se calcule sur le modèle de SURFACE (arbres et toits compris) :
// l'ombre à l'heure choisie (~20 ms), ou les heures de soleil direct de toute
// une journée (~0,7 s, 96 positions du soleil).
//
// La simulation tourne sur une grille de 2 m (quatre fois moins de mailles que
// le relief à 1 m) : une averse d'une heure s'y joue en une quinzaine de
// secondes, et la lame d'eau reste fine à l'échelle d'un talweg.

const SIM_FACTOR = 2
// Une pluie réelle dure des heures, voire des jours : sa simulation tourne sur une
// grille de 4 m et des pas de 1 s, seize fois plus vite qu'à 2 m.
const SIM_FACTOR_LONG = 4
const SIM_DT_LONG = 1
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

// Le domaine, pour la position du soleil. Les ombres ne bougent pas d'un mètre
// sur l'emprise de la grille : un seul point suffit.
const SITE = { lat: 50.3414, lng: 4.9078 }

// Heures de soleil : du peu (indigo) au plein soleil (jaune).
const SUN_RAMP = [
  [0, [30, 27, 75]],
  [0.33, [109, 40, 217]],
  [0.66, [245, 158, 11]],
  [1, [253, 224, 71]],
]

// Hauteur au-dessus du sol : herbe, arbustes, petits arbres, grands arbres.
const CANOPY_RAMP = [
  [0, [231, 222, 196]],
  [0.04, [190, 214, 140]],
  [0.15, [106, 168, 79]],
  [0.4, [39, 110, 52]],
  [1, [12, 54, 28]],
]
const CANOPY_MAX = 30

// Les fonds de « station » : de quoi placer les espèces.
const WETNESS_RAMP = [
  [0, [236, 224, 190]],
  [0.35, [200, 210, 140]],
  [0.55, [110, 175, 100]],
  [0.75, [40, 140, 140]],
  [1, [30, 70, 160]],
]
const FROST_RAMP = [
  [0, [244, 239, 228]],
  [0.33, [205, 222, 240]],
  [0.66, [130, 160, 225]],
  [1, [70, 60, 170]],
]
const BASE_LEGENDS = {
  aspect: 'Orangé : pentes tournées vers le sud, chaudes. Bleu : vers le nord, fraîches. Gris : à plat.',
  landcover: 'Occupation du sol 2023 (SPW, WalOUS) : feuillus, résineux, prairie, revêtement, bâti, eau. C\'est elle qui dit combien la pluie s\'infiltre.',
  wetness: 'Indice topographique (indicatif) : où le relief rassemble l\'eau. Beige sec, vert frais, bleu humide.',
  frost: 'Indice d\'air froid (indicatif) : la nuit, l\'air froid coule comme l\'eau et stagne dans les fonds. Plus c\'est violet, plus le risque de gelée est fort.',
}

// L'occupation du sol (codes WalOUS 2023) : ce que le sol boit (mm/h) et ce
// qu'il peut contenir avant d'être saturé (mm). Ordres de grandeur des modèles
// de ruissellement (sols limoneux à limono-caillouteux du Condroz), pas des
// mesures sur le domaine.
const LANDCOVER = {
  1: { label: 'revêtement', rate: 1, storage: 1, color: [120, 120, 120] },
  2: { label: 'bâti', rate: 0, storage: 0, color: [190, 70, 60] },
  3: { label: 'rail', rate: 10, storage: 30, color: [90, 80, 90] },
  4: { label: 'sol nu', rate: 5, storage: 25, color: [196, 160, 110] },
  5: { label: 'eau', rate: 0, storage: 0, color: [40, 110, 200] },
  6: { label: 'culture', rate: 8, storage: 40, color: [230, 200, 90] },
  7: { label: 'prairie', rate: 15, storage: 50, color: [150, 200, 100] },
  8: { label: 'résineux', rate: 30, storage: 70, color: [30, 90, 60] },
  9: { label: 'feuillus', rate: 50, storage: 80, color: [60, 130, 60] },
  80: { label: 'jeunes résineux', rate: 20, storage: 60, color: [90, 140, 100] },
  90: { label: 'jeunes feuillus', rate: 30, storage: 60, color: [120, 170, 90] },
}
const LANDCOVER_UNKNOWN = { label: 'inconnu', rate: 15, storage: 50, color: [210, 205, 190] }
// L'état du sol au départ : part de la réserve déjà pleine.
const SOIL_STATES = { dry: 0.1, normal: 0.5, wet: 0.9 }

// Les aménagements à l'essai : libellés, couleurs sur le terrain, cotes par défaut.
const DESIGN_LABELS = { swale: 'Baissière', keyline: 'Keyline', pond: 'Mare', hedge: 'Haie sur courbe' }
const DESIGN_COLORS = { swale: '#0284c7', keyline: '#7c3aed', pond: '#0369a1', hedge: '#15803d' }
const DESIGN_HINTS = {
  swale: 'Clique le début de la baissière sur le terrain, puis vers où elle doit s\'étendre : elle suit la courbe de niveau.',
  keyline: 'Clique le départ (le point haut), puis vers où l\'eau doit aller : la ligne descend doucement le long de la pente.',
  pond: 'Clique le centre de la mare sur le terrain.',
  hedge: 'Clique le début de la haie, puis vers où elle s\'étend : elle suit la courbe de niveau. Sur une pente raide, elle freine et boit l\'eau sans terrassement.',
}

const LAYER_COLORS = 

{ venues: '#f59e0b', management: '#fafaf9', welcome: '#a3e635' }

export default class extends Controller {
  static targets = [
    'viewport', 'loading', 'panel', 'panelBody', 'exaggeration', 'exaggerationLabel',
    'playButton', 'playLabel', 'clock', 'rainState', 'stats', 'probe',
    'baseLegend', 'designHint', 'designList', 'designSwaleOptions', 'designPondOptions', 'designGradeOptions', 'designHedgeOptions', 'plantStatus', 'rainTypical', 'rainReal', 'rainDate', 'rainChart', 'rainRealStatus', 'soilUniform', 'sunSection', 'sunHour', 'sunHourLabel', 'sunHourRow', 'sunStatus', 'sunLegend', 'sunLegendMax', 'dayButton', 'dayLabel', 'surfaceToggle',
  ]

  static values = {
    gridUrl: String,
    textureUrl: String,
    surfaceUrl: String,
    surfaceMeta: Object,
    landcoverUrl: String,
    meta: Object,
    featuresUrl: String,
    featureLayers: Array,
    designsUrl: String,
    plantsLayer: String,
    domain: Object,
  }

  async connect() {
    this.settings = {
      base: 'ortho', contour: 5, axes: true, hollows: true, features: true, particles: true,
      intensity: 30, duration: 60, infiltration: 10, speed: 4,
      sunMode: 'off', sunDate: '06-21', solidSurface: false,
      width: 2, depth: 0.5, berm: 0.4, grade: 1, radius: 5, pondDepth: 1.5, hedgeWidth: 5, hedgeBerm: 0,
      soilState: 'normal', rainSource: 'typical', realDays: 3, plantMode: 'off', plantFilter: 'all',
    }
    this.playing = false
    this.features = []
    this.designs = []
    this.tool = null
    try {
      await this.load()
    } catch (error) {
      console.error(error)
      this.setLoading(`Le relief n'a pas pu s'afficher : ${error.message}`, true)
    }
  }

  disconnect() {
    this.disposed = true
    clearInterval(this.dayTimer)
    this.scene?.dispose()
  }

  async load() {
    this.setLoading('Chargement du relief…')
    const [response, surfaceResponse, landcoverResponse, { ReliefScene }] = await Promise.all([
      fetch(this.gridUrlValue, { credentials: 'same-origin' }),
      this.surfaceUrlValue ? fetch(this.surfaceUrlValue, { credentials: 'same-origin' }).catch(() => null) : null,
      this.landcoverUrlValue ? fetch(this.landcoverUrlValue, { credentials: 'same-origin' }).catch(() => null) : null,
      import('../utils/map_relief_scene'),
    ])
    if (!response.ok) throw new Error(`grille indisponible (${response.status})`)
    const meta = this.metaValue
    const full = decodeGrid(await response.arrayBuffer(), meta)
    // Sans modèle de surface, les ombres tombent du seul relief.
    this.surface = surfaceResponse?.ok
      ? decodeGrid(await surfaceResponse.arrayBuffer(), { ...meta, ...this.surfaceMetaValue })
      : null
    // L'occupation du sol (un octet par maille) : sans elle, le sol boit
    // partout pareil, au rythme choisi à la main.
    this.landcover = landcoverResponse?.ok ? new Uint8Array(await landcoverResponse.arrayBuffer()) : null
    if (this.landcover && this.hasSoilUniformTarget) this.soilUniformTarget.classList.add('hidden')
    if (this.disposed) return
    if (!this.surface && this.hasSurfaceToggleTarget) this.surfaceToggleTarget.closest('label').classList.add('hidden')

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
    this.designs = await this.fetchDesigns()
    await nextPaint()
    this.reshape({ keepMesh: !this.designs.length })
    // Après `reshape` : les capacités des ouvrages sont calculées.
    this.renderDesignList()
    this.hypsometryTexture = this.scene.canvasTexture(this.hypsometryCanvas())
    await this.applyBase()
    this.drawOverlay()
    this.setLoading(null)
    this.loadFeatures()
    this.loadPlants()
  }

  // ---- Réglages de la vue ---------------------------------------------------

  async setBase(event) {
    this.settings.base = event.params.value
    this.markChoice(event)
    await this.applyBase()
  }

  async applyBase() {
    const base = this.settings.base
    if (this.hasBaseLegendTarget) {
      this.baseLegendTarget.textContent = BASE_LEGENDS[base] || ''
      this.baseLegendTarget.classList.toggle('hidden', !BASE_LEGENDS[base])
    }
    if (BASE_LEGENDS[base]) {
      await this.ensureStation()
      this.stationTextures ||= {}
      this.stationTextures[base] ||= this.scene.canvasTexture(this.stationCanvas(base))
      return this.scene.setBaseTexture(this.stationTextures[base])
    }
    if (this.settings.base === 'canopy' && this.surface) {
      this.canopyTexture ||= this.scene.canvasTexture(this.canopyCanvas())
      return this.scene.setBaseTexture(this.canopyTexture)
    }
    if (this.settings.base === 'ortho' && this.hasTextureUrlValue && this.textureUrlValue) {
      this.orthoTexture ||= await this.scene.loadImageTexture(this.textureUrlValue).catch(() => null)
      if (this.orthoTexture) return this.scene.setBaseTexture(this.orthoTexture)
    }
    this.scene.setBaseTexture(this.hypsometryTexture)
  }

  // Pente, exposition, humidité et gel : ~1 s de calcul, fait une fois, à la
  // première demande (un fond de station ou un clic sur le terrain).
  async ensureStation() {
    if (this.station) return this.station
    this.setLoading('Calcul de la station (pente, humidité, gel)…')
    await nextPaint()
    const { cols, rows } = this.full
    const heights = this.ground
    const cell = this.metaValue.cell_size_m
    const { slope, aspect } = slopeAspect(heights, cols, rows, cell)
    const spread = spreadAccumulation(this.drainage, cols, rows, cell)
    const wetness = boxBlur(wetnessIndex(spread, slope, cell), cols, rows, 2)
    const frost = boxBlur(frostRisk(heights, this.drainage), cols, rows, 2)
    this.station = { slope, aspect, wetness, frost, spread }
    this.setLoading(null)
    return this.station
  }

  stationCanvas(kind) {
    const { cols, rows } = this.full
    const { slope, aspect, wetness, frost } = this.station
    const canvas = document.createElement('canvas')
    canvas.width = cols
    canvas.height = rows
    const context = canvas.getContext('2d')
    const image = context.createImageData(cols, rows)
    const data = image.data
    for (let i = 0; i < cols * rows; i++) {
      let color
      if (kind === 'aspect') {
        // Du nord (bleu) au sud (orangé) en passant par l'est et l'ouest
        // (neutres) ; une pente faible tire vers le gris.
        const southness = -Math.cos(aspect[i])
        const strength = Math.min(1, Math.tan(slope[i]) / 0.25)
        const tone = southness >= 0 ? [232, 119, 46] : [59, 111, 182]
        const neutral = [222, 216, 200]
        const t = Math.abs(southness) * strength
        color = neutral.map((v, j) => Math.round(v + (tone[j] - v) * t))
      } else if (kind === 'landcover') {
        color = this.landcover ? (LANDCOVER[this.landcover[i]] || LANDCOVER_UNKNOWN).color : LANDCOVER_UNKNOWN.color
      } else if (kind === 'wetness') {
        color = ramp((wetness[i] - 3) / 9, WETNESS_RAMP)
      } else {
        color = ramp(frost[i], FROST_RAMP)
      }
      data[i * 4] = color[0]
      data[i * 4 + 1] = color[1]
      data[i * 4 + 2] = color[2]
      data[i * 4 + 3] = 255
    }
    context.putImageData(image, 0, 0)
    return canvas
  }

  setExaggeration() {
    const value = Number(this.exaggerationTarget.value)
    this.exaggerationLabelTarget.textContent = `×${formatNumber(value, 1)}`
    this.scene?.setExaggeration(value)
    if (this.settings.solidSurface) this.applySurfaceHeights()
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

  // ---- Le soleil ------------------------------------------------------------

  setSunMode(event) {
    this.settings.sunMode = event.params.value
    this.markChoice(event)
    this.stopDay()
    this.renderSun()
  }

  setSunDate(event) {
    this.settings.sunDate = event.params.value
    this.markChoice(event)
    this.dayHours = null
    this.renderSun()
  }

  setSunHour() {
    this.renderSun()
  }

  // Le maillage montre les arbres et les toits, ou le terrain nu.
  toggleSurface(event) {
    this.settings.solidSurface = event.target.checked
    this.applySurfaceHeights()
  }

  // Le terrain est exagéré, les arbres et les toits non : le groupe de la scène
  // multiplie toute hauteur par l'exagération, on divise donc d'avance ce qui
  // dépasse du sol. Un chêne de 30 m reste un chêne de 30 m sur un relief ×3.
  applySurfaceHeights() {
    if (!this.scene) return
    const ground = this.ground || this.full.heights
    let heights = ground
    if (this.surface && this.settings.solidSurface) {
      const exaggeration = Number(this.exaggerationTarget.value) || 1
      const original = this.full.heights
      heights = new Float32Array(ground.length)
      for (let i = 0; i < ground.length; i++) heights[i] = ground[i] + (this.surface[i] - original[i]) / exaggeration
    }
    this.scene.setHeights(downsample(heights, this.full.cols, this.full.rows, this.meshFactor).heights)
  }

  // « Faire passer la journée » : l'heure avance de 10 min tous les dixièmes
  // de seconde, du lever au coucher.
  toggleDay() {
    if (this.dayTimer) return this.stopDay()
    if (this.settings.sunMode !== 'instant') this.forceSunMode('instant')
    const slider = this.sunHourTarget
    if (Number(slider.value) >= Number(slider.max)) slider.value = slider.min
    this.dayTimer = setInterval(() => {
      const next = Number(slider.value) + 10
      if (next > Number(slider.max)) return this.stopDay()
      slider.value = next
      this.renderSun()
    }, 100)
    this.dayLabelTarget.textContent = 'Arrêter'
  }

  stopDay() {
    clearInterval(this.dayTimer)
    this.dayTimer = null
    if (this.hasDayLabelTarget) this.dayLabelTarget.textContent = 'Faire passer la journée'
  }

  forceSunMode(mode) {
    this.settings.sunMode = mode
    this.element.querySelectorAll('[data-choice-group="sunMode"] [aria-pressed]').forEach((button) => {
      button.setAttribute('aria-pressed', String(button.dataset.mapReliefValueParam === mode))
    })
  }

  sunDay() {
    const today = new Date()
    if (this.settings.sunDate === 'today') return new Date(today.getFullYear(), today.getMonth(), today.getDate())
    const [month, day] = this.settings.sunDate.split('-').map(Number)
    return new Date(today.getFullYear(), month - 1, day)
  }

  sunInstant() {
    const minutes = Number(this.sunHourTarget.value)
    const day = this.sunDay()
    return new Date(day.getFullYear(), day.getMonth(), day.getDate(), Math.floor(minutes / 60), minutes % 60)
  }

  async renderSun() {
    if (!this.scene) return
    const mode = this.settings.sunMode
    this.sunHourRowTarget.classList.toggle('hidden', mode !== 'instant')
    this.sunLegendTarget.classList.toggle('hidden', mode !== 'hours')
    const minutes = Number(this.sunHourTarget.value)
    this.sunHourLabelTarget.textContent = `${Math.floor(minutes / 60)} h ${String(minutes % 60).padStart(2, '0')}`
    const { cols, rows } = this.full
    const surface = this.surface || this.full.heights
    if (mode === 'off') {
      this.scene.setSun(null)
      this.scene.setSunTint(null)
      this.sunStatusTarget.textContent = ''
      return
    }
    if (mode === 'instant') {
      const sun = sunPosition(this.sunInstant(), SITE.lat, SITE.lng)
      this.scene.setSun(sun)
      if (sun.altitude <= 0) {
        this.sunStatusTarget.textContent = 'Le soleil est couché.'
        this.lastMask = null
        return this.scene.setSunTint(this.uniformTint([20, 24, 48, 120]), cols, rows)
      }
      this.maskBuffer ||= new Uint8Array(cols * rows)
      this.levelBuffer ||= new Float32Array(cols * rows)
      const mask = shadowMask(surface, cols, rows, this.metaValue.cell_size_m, sun, this.maskBuffer, this.levelBuffer)
      this.lastMask = mask
      const tint = this.tintBuffer()
      let shaded = 0
      for (let i = 0; i < mask.length; i++) {
        const o = i * 4
        if (mask[i]) { tint[o + 3] = 0; continue }
        shaded++
        tint[o] = 18; tint[o + 1] = 22; tint[o + 2] = 58; tint[o + 3] = 175
      }
      this.scene.setSunTint(tint, cols, rows)
      this.sunStatusTarget.textContent = `Soleil à ${Math.round(sun.altitude / (Math.PI / 180))}° au-dessus de l'horizon, ${compass(sun.azimuth)} ; ${Math.round(shaded / mask.length * 100)} % de la zone à l'ombre.`
      return
    }
    // Les heures de soleil de la journée : calculées une fois par date.
    this.scene.setSun(null)
    if (!this.dayHours || this.dayHours.date !== this.settings.sunDate) {
      const date = this.settings.sunDate
      this.sunStatusTarget.textContent = 'Calcul des heures de soleil…'
      const result = await sunHours(surface, cols, rows, this.metaValue.cell_size_m, SITE.lat, SITE.lng, this.sunDay(), {
        onProgress: (f) => { this.sunStatusTarget.textContent = `Calcul des heures de soleil… ${Math.round(f * 100)} %` },
      })
      if (this.settings.sunDate !== date || this.settings.sunMode !== 'hours') return
      this.dayHours = { ...result, date }
    }
    const { hours, daylight } = this.dayHours
    const tint = this.tintBuffer()
    for (let i = 0; i < hours.length; i++) {
      const [r, g, b] = ramp(hours[i] / daylight, SUN_RAMP)
      const o = i * 4
      tint[o] = r; tint[o + 1] = g; tint[o + 2] = b; tint[o + 3] = 175
    }
    this.scene.setSunTint(tint, cols, rows)
    this.sunLegendMaxTarget.textContent = formatHours(daylight)
    this.sunStatusTarget.textContent = `Jour de ${formatHours(daylight)} : chaque mètre carré est teinté selon ses heures de soleil direct.`
  }

  tintBuffer() {
    const size = this.full.cols * this.full.rows * 4
    if (this.tint?.length !== size) this.tint = new Uint8Array(size)
    return this.tint
  }

  uniformTint([r, g, b, a]) {
    const tint = this.tintBuffer()
    for (let o = 0; o < tint.length; o += 4) { tint[o] = r; tint[o + 1] = g; tint[o + 2] = b; tint[o + 3] = a }
    return tint
  }

  canopyCanvas() {
    const { heights, cols, rows } = this.full
    const canvas = document.createElement('canvas')
    canvas.width = cols
    canvas.height = rows
    const context = canvas.getContext('2d')
    const image = context.createImageData(cols, rows)
    for (let i = 0; i < heights.length; i++) {
      const [r, g, b] = ramp(Math.max(0, this.surface[i] - heights[i]) / CANOPY_MAX, CANOPY_RAMP)
      image.data[i * 4] = r
      image.data[i * 4 + 1] = g
      image.data[i * 4 + 2] = b
      image.data[i * 4 + 3] = 255
    }
    context.putImageData(image, 0, 0)
    return canvas
  }

  // ---- Les aménagements à l'essai -------------------------------------------

  // Le relief creusé des aménagements, et tout ce qui en dépend : maillage,
  // axes d'écoulement, station, simulations. ~0,4 s.
  reshape({ keepMesh = false } = {}) {
    const { heights, cols, rows } = this.full
    const cell = this.metaValue.cell_size_m
    // Un aménagement masqué ne creuse rien : il reste dans la liste, sans effet.
    this.designs.filter((design) => design.enabled === false).forEach((design) => {
      design.cells = null
      design.simCells = []
      design.capacity = 0
    })
    const active = this.designs.filter((design) => design.enabled !== false)
    if (active.length) {
      const result = applyDesigns(heights, cols, rows, cell, active)
      this.ground = result.heights
      result.footprints.forEach((footprint) => {
        const design = this.designs.find((d) => d.id === footprint.id)
        if (!design) return
        design.capacity = footprint.capacity
        design.cells = footprint.cells
        design.hedge = !!footprint.hedge
        design.simCells = null
      })
    } else {
      this.ground = heights
    }
    if (!keepMesh) this.applySurfaceHeights()
    this.drainage = analyzeDrainage(this.ground, cols, rows, cell)
    this.station = null
    this.stationTextures = null
    if (this.simulation) {
      this.buildSimulations()
      this.scene.clearWater()
    }
  }

  // Deux simulations côte à côte : le terrain creusé, et le terrain actuel
  // pour comparer (seulement s'il y a des aménagements).
  buildSimulations() {
    const { heights, cols, rows } = this.full
    const factor = this.simFactor
    const cell = this.metaValue.cell_size_m * factor
    const base = downsample(heights, cols, rows, factor)
    const designed = this.activeDesigns.length ? downsampleDesigned(heights, this.ground, cols, rows, factor) : base.heights
    this.baseSoilMaps = this.buildSoilMaps(base.cols, base.rows, factor, null)
    this.soilMaps = this.buildSoilMaps(base.cols, base.rows, factor, this.hedgeMask())
    this.domainCells = null
    this.designs.forEach((design) => { design.simCells = design.cells ? this.toSimCells(design.cells) : [] })
    this.simulation = new RainSimulation(designed, base.cols, base.rows, cell, this.simOptions())
    this.baseline = this.activeDesigns.length ? new RainSimulation(base.heights, base.cols, base.rows, cell, this.simOptions(true)) : null
    // Le relief a changé : la pluie repart de zéro, à la main.
    this.playing = false
    if (this.hasPlayLabelTarget) this.playLabelTarget.textContent = 'Faire pleuvoir'
    if (this.hasPlayButtonTarget) this.playButtonTarget.setAttribute('aria-pressed', 'false')
    this.renderStats()
  }

  get activeDesigns() { return this.designs.filter((design) => design.enabled !== false) }

  toSimCells(cells) {
    const { cols } = this.full
    const factor = this.simFactor
    const simCols = Math.floor(cols / factor)
    const set = new Set()
    for (const i of cells) {
      const c = i % cols
      const r = (i - c) / cols
      set.add(Math.floor(r / factor) * simCols + Math.floor(c / factor))
    }
    return [...set]
  }

  // L'eau présente dans l'empreinte d'un ouvrage (m³).
  designWater(design) {
    const sim = this.simulation
    if (!sim || !design.simCells) return 0
    const area = sim.cellSize * sim.cellSize
    let volume = 0
    for (const i of design.simCells) volume += sim.depth[i] * area
    return volume
  }

  chooseTool(event) {
    const tool = event.params.value
    this.tool = this.tool === tool ? null : tool
    this.pending = null
    this.element.querySelectorAll('[data-choice-group="designTool"] [aria-pressed]').forEach((button) => {
      button.setAttribute('aria-pressed', String(button.dataset.mapReliefValueParam === this.tool))
    })
    this.designHintTarget.textContent = this.tool ? DESIGN_HINTS[this.tool] : ''
    this.designSwaleOptionsTarget.classList.toggle('hidden', !['swale', 'keyline'].includes(this.tool))
    this.designGradeOptionsTarget.classList.toggle('hidden', this.tool !== 'keyline')
    this.designPondOptionsTarget.classList.toggle('hidden', this.tool !== 'pond')
    if (this.hasDesignHedgeOptionsTarget) this.designHedgeOptionsTarget.classList.toggle('hidden', this.tool !== 'hedge')
    this.drawOverlay()
  }

  setDesignOption(event) {
    this.settings[event.params.key] = Number(event.params.value)
    this.markChoice(event)
  }

  // Un clic sur le terrain, outil en main : le centre d'une mare, ou les deux
  // points d'une baissière / keyline.
  async placeDesign(event) {
    const hit = this.scene.pick(event)
    if (!hit) return
    const cell = this.metaValue.cell_size_m
    const point = { x: hit.col * this.meshFactor * cell, y: hit.row * this.meshFactor * cell }
    const { heights, cols, rows } = this.full
    let design
    if (this.tool === 'pond') {
      design = { type: 'pond', center: point, radius: this.settings.radius, depth: this.settings.pondDepth, berm: 0.3 }
    } else if (!this.pending) {
      this.pending = point
      this.designHintTarget.textContent = this.tool === 'hedge'
        ? 'Maintenant, clique vers où la haie doit s\'étendre.'
        : this.tool === 'keyline'
        ? 'Maintenant, clique vers où l\'eau doit aller.'
        : 'Maintenant, clique vers où la baissière doit s\'étendre.'
      this.drawOverlay()
      return
    } else {
      const grade = this.tool === 'keyline' ? this.settings.grade : 0
      const trace = traceContour(heights, cols, rows, cell, this.pending, point, { grade })
      this.pending = null
      if (trace.length < 3) {
        this.designHintTarget.textContent = 'Trop court ou sur un replat : reclique un départ ailleurs.'
        this.drawOverlay()
        return
      }
      design = this.tool === 'hedge'
        ? { type: 'hedge', points: trace.points, width: this.settings.hedgeWidth, berm: this.settings.hedgeBerm, grade: 0,
            length: trace.length }
        : { type: this.tool, points: trace.points, width: this.settings.width, depth: this.settings.depth,
            berm: this.settings.berm, grade, length: trace.length }
    }
    this.designHintTarget.textContent = 'Enregistrement…'
    try {
      const saved = await this.saveDesign(design)
      this.designs.push(saved)
      this.designHintTarget.textContent = `${saved.name} posée. ${DESIGN_HINTS[this.tool]}`
    } catch (error) {
      this.designHintTarget.textContent = `Pas enregistré : ${error.message}`
      return
    }
    this.setLoading('Mise à jour du relief…')
    await nextPaint()
    this.reshape()
    await this.applyBase()
    this.drawOverlay()
    this.renderDesignList()
    this.setLoading(null)
  }

  async removeDesign(event) {
    const id = event.params.id
    const response = await fetch(`${this.designsUrlValue}/${id}`, {
      method: 'DELETE', headers: { 'X-CSRF-Token': csrfToken(), Accept: 'application/json' }, credentials: 'same-origin',
    })
    if (!response.ok) return
    this.designs = this.designs.filter((design) => String(design.id) !== String(id))
    this.setLoading('Mise à jour du relief…')
    await nextPaint()
    this.reshape()
    await this.applyBase()
    this.drawOverlay()
    this.renderDesignList()
    this.setLoading(null)
  }

  // La liste du panneau se dessine APRÈS que l'appelant a rangé le résultat
  // dans `this.designs` : la dessiner ici montrait « Aucun aménagement » au
  // chargement alors que les ouvrages étaient bien tracés sur le relief.
  async fetchDesigns() {
    if (!this.designsUrlValue) return []
    try {
      const response = await fetch(this.designsUrlValue, { headers: { Accept: 'application/json' }, credentials: 'same-origin' })
      if (!response.ok) return []
      const collection = await response.json()
      return (collection.features || []).map((feature) => this.fromFeature(feature)).filter(Boolean)
    } catch {
      return []
    }
  }

  async saveDesign(design) {
    const body = {
      design: {
        type: design.type,
        geometry: JSON.stringify(this.toGeometry(design)),
        width: design.width, depth: design.depth, berm: design.berm, grade: design.grade, radius: design.radius,
        center: design.center ? this.toLngLat(design.center) : undefined,
      },
    }
    const response = await fetch(this.designsUrlValue, {
      method: 'POST', credentials: 'same-origin',
      headers: { 'Content-Type': 'application/json', Accept: 'application/json', 'X-CSRF-Token': csrfToken() },
      body: JSON.stringify(body),
    })
    const json = await response.json().catch(() => ({}))
    if (!response.ok) throw new Error((json.errors || [response.status]).join(', '))
    return this.fromFeature(json)
  }

  // GeoJSON ↔ aménagement en mètres sur la grille.
  fromFeature(feature) {
    const props = feature.properties || {}
    const design = props.design || {}
    if (!design.type) return null
    const base = { id: feature.id, name: props.name, type: design.type, width: design.width, depth: design.depth, enabled: design.enabled !== false,
                   berm: design.berm, grade: design.grade || 0, radius: design.radius }
    if (design.type === 'pond') {
      const center = design.center || polygonCenter(feature.geometry)
      return center ? { ...base, center: this.toGrid(center) } : null
    }
    const coordinates = feature.geometry?.coordinates || []
    const points = coordinates.map((position) => this.toGrid(position))
    // Le niveau visé de chaque point : la pente de la keyline depuis le départ.
    const { heights, cols, rows } = this.full
    const cell = this.metaValue.cell_size_m
    let travelled = 0
    const z0 = points.length ? heightFromGrid(heights, cols, rows, cell, points[0]) : 0
    points.forEach((point, k) => {
      if (k) travelled += Math.hypot(point.x - points[k - 1].x, point.y - points[k - 1].y)
      point.z = z0 - ((design.grade || 0) / 100) * travelled
    })
    return { ...base, points, length: travelled }
  }

  toGeometry(design) {
    if (design.type === 'pond') {
      const ring = []
      for (let k = 0; k <= 32; k++) {
        const angle = (k % 32) / 32 * Math.PI * 2
        ring.push(this.toLngLat({ x: design.center.x + Math.cos(angle) * design.radius,
                                  y: design.center.y + Math.sin(angle) * design.radius }))
      }
      return { type: 'Polygon', coordinates: [ring] }
    }
    return { type: 'LineString', coordinates: design.points.map((point) => this.toLngLat(point)) }
  }

  toLngLat({ x, y }) {
    const meta = this.metaValue
    const mx = meta.west + (x / meta.cell_size_m) * meta.step
    const my = meta.north - (y / meta.cell_size_m) * meta.step
    const radius = 6378137
    const lng = (mx / radius) * 180 / Math.PI
    const lat = (2 * Math.atan(Math.exp(my / radius)) - Math.PI / 2) * 180 / Math.PI
    return [Number(lng.toFixed(7)), Number(lat.toFixed(7))]
  }

  toGrid([lng, lat]) {
    const meta = this.metaValue
    const [mx, my] = toMercator(lat, lng)
    return { x: ((mx - meta.west) / meta.step) * meta.cell_size_m, y: ((meta.north - my) / meta.step) * meta.cell_size_m }
  }

  drawDesigns(context, canvas) {
    const meta = this.metaValue
    const sx = canvas.width / ((meta.cols - 1) * meta.cell_size_m)
    const sy = canvas.height / ((meta.rows - 1) * meta.cell_size_m)
    context.save()
    context.lineCap = 'round'
    context.lineJoin = 'round'
    // Le survolé d'abord, sous les autres : un halo jaune large, même s'il est masqué.
    const highlighted = this.designs.find((design) => String(design.id) === String(this.highlightId))
    if (highlighted) this.drawHalo(context, highlighted, sx, sy)
    for (const design of this.designs) {
      if (design.enabled === false) continue
      context.strokeStyle = DESIGN_COLORS[design.type]
      context.fillStyle = DESIGN_COLORS[design.type]
      if (design.type === 'pond') {
        context.globalAlpha = 0.35
        context.beginPath()
        context.ellipse(design.center.x * sx, design.center.y * sy, design.radius * sx, design.radius * sy, 0, 0, Math.PI * 2)
        context.fill()
        context.globalAlpha = 1
        context.strokeStyle = '#ffffff'
        context.lineWidth = 7
        context.stroke()
        context.strokeStyle = DESIGN_COLORS.pond
        context.lineWidth = 4
        context.stroke()
        continue
      }
      // Une haie : une bande verte de sa largeur, ponctuée d'arbres tous les 3 m.
      if (design.type === 'hedge') {
        const band = Math.max(4, (design.width || 5) * sx)
        // Un liseré clair d'abord : vert sur vert, la bande se perdait dans la prairie.
        const trace = () => {
          context.beginPath()
          design.points.forEach((point, k) => {
            if (k === 0) context.moveTo(point.x * sx, point.y * sy)
            else context.lineTo(point.x * sx, point.y * sy)
          })
        }
        context.globalAlpha = 0.85
        context.strokeStyle = '#fef9c3'
        context.lineWidth = band + 5
        trace()
        context.stroke()
        context.globalAlpha = 0.85
        context.strokeStyle = DESIGN_COLORS.hedge
        context.lineWidth = band
        trace()
        context.stroke()
        context.globalAlpha = 1
        context.fillStyle = '#14532d'
        design.points.forEach((point, k) => {
          if (k % 3) return
          context.beginPath()
          context.arc(point.x * sx, point.y * sy, Math.max(3, band * 0.3), 0, Math.PI * 2)
          context.fill()
        })
        continue
      }
      // Un liseré blanc sous le trait : lisible sur l'ortho comme sur les fonds
      // de station.
      const width = Math.max(6, (design.width || 2) * sx)
      const path = () => {
        context.beginPath()
        design.points.forEach((point, k) => {
          if (k === 0) context.moveTo(point.x * sx, point.y * sy)
          else context.lineTo(point.x * sx, point.y * sy)
        })
      }
      context.globalAlpha = 0.9
      context.strokeStyle = '#ffffff'
      context.lineWidth = width + 4
      path()
      context.stroke()
      context.globalAlpha = 1
      context.strokeStyle = DESIGN_COLORS[design.type]
      context.lineWidth = width
      context.setLineDash(design.type === 'keyline' ? [14, 8] : [])
      path()
      context.stroke()
      context.setLineDash([])
      // Une keyline mène l'eau : une pointe à son extrémité basse.
      if (design.type === 'keyline' && design.points.length > 1) {
        const a = design.points[design.points.length - 2]
        const b = design.points[design.points.length - 1]
        const angle = Math.atan2((b.y - a.y) * sy, (b.x - a.x) * sx)
        context.beginPath()
        context.moveTo(b.x * sx + Math.cos(angle) * 10, b.y * sy + Math.sin(angle) * 10)
        context.lineTo(b.x * sx + Math.cos(angle + 2.5) * 10, b.y * sy + Math.sin(angle + 2.5) * 10)
        context.lineTo(b.x * sx + Math.cos(angle - 2.5) * 10, b.y * sy + Math.sin(angle - 2.5) * 10)
        context.closePath()
        context.fill()
      }
    }
    if (this.pending) {
      context.globalAlpha = 1
      context.fillStyle = '#f97316'
      context.beginPath()
      context.arc(this.pending.x * sx, this.pending.y * sy, 7, 0, Math.PI * 2)
      context.fill()
    }
    context.restore()
  }

  drawHalo(context, design, sx, sy) {
    context.save()
    context.strokeStyle = '#facc15'
    context.globalAlpha = 0.95
    context.lineCap = 'round'
    context.lineJoin = 'round'
    if (design.type === 'pond') {
      context.lineWidth = 14
      context.beginPath()
      context.ellipse(design.center.x * sx, design.center.y * sy, (design.radius + 2) * sx, (design.radius + 2) * sy, 0, 0, Math.PI * 2)
      context.stroke()
    } else {
      context.lineWidth = Math.max(16, (design.width || 2) * sx + 14)
      context.beginPath()
      design.points.forEach((point, k) => {
        if (k === 0) context.moveTo(point.x * sx, point.y * sy)
        else context.lineTo(point.x * sx, point.y * sy)
      })
      context.stroke()
    }
    context.restore()
  }

  // Le survol d'un aménagement dans la liste : halo sur le terrain et balise.
  highlightDesign(event) {
    const id = event.params.id
    if (String(this.highlightId) === String(id)) return
    this.highlightId = id
    const design = this.designs.find((d) => String(d.id) === String(id))
    if (design) this.scene?.setBeacon(this.designAnchor(design))
    this.drawOverlay()
  }

  clearHighlight() {
    if (this.highlightId == null) return
    this.highlightId = null
    this.scene?.setBeacon(null)
    this.drawOverlay()
  }

  // Le point où planter la balise : le centre d'une mare, le milieu d'une ligne.
  designAnchor(design) {
    const point = design.type === 'pond' ? design.center : design.points[Math.floor(design.points.length / 2)]
    const { cols, rows } = this.full
    const cell = this.metaValue.cell_size_m
    const c = Math.min(cols - 1, Math.max(0, Math.round(point.x / cell)))
    const r = Math.min(rows - 1, Math.max(0, Math.round(point.y / cell)))
    return { x: point.x, z: point.y, ground: this.full.heights[r * cols + c], size: design.radius || design.width || 4 }
  }

  // Masquer / réafficher sans supprimer : enregistré (on le retrouve au
  // rechargement), et le relief simulé est recalculé sans lui.
  async toggleDesign(event) {
    const id = event.params.id
    const design = this.designs.find((d) => String(d.id) === String(id))
    if (!design) return
    const enabled = design.enabled === false
    const response = await fetch(`${this.designsUrlValue}/${id}`, {
      method: 'PATCH', credentials: 'same-origin',
      headers: { 'Content-Type': 'application/json', Accept: 'application/json', 'X-CSRF-Token': csrfToken() },
      body: JSON.stringify({ design: { enabled } }),
    })
    if (!response.ok) return
    design.enabled = enabled
    this.setLoading('Mise à jour du relief…')
    await nextPaint()
    this.reshape()
    await this.applyBase()
    this.drawOverlay()
    this.renderDesignList()
    this.setLoading(null)
  }

  renderDesignList() {
    if (!this.hasDesignListTarget) return
    if (!this.designs.length) {
      this.designListTarget.innerHTML = '<li class="text-xs text-stone-400">Aucun aménagement pour l\'instant.</li>'
      return
    }
    const raining = this.simulation && this.simulation.time > 0
    this.designListTarget.innerHTML = this.designs.map((design) => {
      const size = design.type === 'hedge'
        ? `${formatNumber(design.length || 0, 0)} m × ${formatNumber(design.width || 5, 0)} m`
        : design.type === 'pond'
        ? `r ${formatNumber(design.radius, 0)} m, ${formatNumber(design.depth, 1)} m`
        : `${formatNumber(design.length || 0, 0)} m${design.grade ? `, ${formatNumber(design.grade, 1)} %` : ''}`
      const water = raining ? ` · ${formatVolume(this.designWater(design))} d'eau` : ''
      const off = design.enabled === false
      const eye = off
        ? '<path d="M3 3l18 18M10.6 10.6a2 2 0 0 0 2.8 2.8M9.9 5.1A9.8 9.8 0 0 1 12 5c5 0 9 4.5 10 7a12.6 12.6 0 0 1-3.2 4.2M6.6 6.6C4.3 8 2.7 10.2 2 12c1 2.5 5 7 10 7a9.6 9.6 0 0 0 4.5-1.1"/>'
        : '<path d="M2 12c1-2.5 5-7 10-7s9 4.5 10 7c-1 2.5-5 7-10 7S3 14.5 2 12z"/><circle cx="12" cy="12" r="3"/>'
      return `<li class="flex items-center gap-2 rounded px-1 text-xs hover:bg-amber-50 ${off ? 'opacity-50' : ''}"
                  data-action="mouseenter->map-relief#highlightDesign mouseleave->map-relief#clearHighlight"
                  data-map-relief-id-param="${design.id}">
        <button type="button" class="shrink-0 rounded p-0.5 text-stone-500 hover:bg-stone-100 hover:text-stone-800"
                data-action="map-relief#toggleDesign" data-map-relief-id-param="${design.id}"
                aria-pressed="${off ? 'false' : 'true'}" title="${off ? 'Réafficher' : 'Masquer'}" aria-label="${off ? 'Réafficher' : 'Masquer'} ${escapeHtml(design.name || '')}">
          <svg class="h-3.5 w-3.5" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${eye}</svg>
        </button>
        <span class="h-2.5 w-2.5 shrink-0 rounded-full" style="background:${DESIGN_COLORS[design.type]}"></span>
        <span class="min-w-0 flex-1 break-words leading-tight text-stone-700">${escapeHtml(design.name || DESIGN_LABELS[design.type])} <span class="text-stone-400">(${size})</span></span>
        <span class="shrink-0 tabular-nums text-stone-500">${design.type === 'keyline' ? 'mène l\'eau' : design.type === 'hedge' ? `boit ~${HEDGE_SOIL.rate} mm/h` : `${formatVolume(design.capacity || 0)} max`}${water}</span>
        <button type="button" class="shrink-0 rounded px-1 text-stone-400 hover:bg-stone-100 hover:text-red-700"
                data-action="map-relief#removeDesign" data-map-relief-id-param="${design.id}" aria-label="Retirer ${escapeHtml(design.name || '')}">×</button>
      </li>`
    }).join('')
  }

  // ---- Les plantes nourricières ----------------------------------------------

  // Les plantes PLACÉES (un point dans la couche Plantes), avec leurs
  // dimensions adultes calculées côté serveur (espèce + conduite, ou saisie).
  async loadPlants() {
    if (!this.plantsLayerValue) return
    try {
      const url = `${this.featuresUrlValue}?layer_id=${encodeURIComponent(this.plantsLayerValue)}`
      const response = await fetch(url, { headers: { Accept: 'application/json' }, credentials: 'same-origin' })
      if (!response.ok) return
      const collection = await response.json()
      const { cols, rows } = this.full
      const cell = this.metaValue.cell_size_m
      this.allPlants = (collection.features || [])
        .filter((feature) => feature.geometry?.type === 'Point' && !feature.properties?.dead)
        .map((feature) => {
          const p = feature.properties
          const { x, y } = this.toGrid(feature.geometry.coordinates)
          const c = Math.min(cols - 1, Math.max(0, Math.round(x / cell)))
          const r = Math.min(rows - 1, Math.max(0, Math.round(y / cell)))
          return {
            id: p.plant_id, name: p.name, species: p.species, status: p.status, planned: !!p.planned,
            stratum: p.stratum, height: p.mature?.height || 8, spread: p.mature?.spread || 6, source: p.mature?.source,
            x, z: y, ground: this.full.heights[r * cols + c],
          }
        })
        .filter((plant) => plant.x >= 0 && plant.z >= 0 && plant.x <= (cols - 1) * cell && plant.z <= (rows - 1) * cell)
    } catch {
      this.allPlants = []
    }
    this.applyPlants()
  }

  setPlantMode(event) {
    this.settings.plantMode = event.params.value
    this.markChoice(event)
    this.applyPlants()
  }

  setPlantFilter(event) {
    this.settings.plantFilter = event.params.value
    this.markChoice(event)
    this.applyPlants()
  }

  applyPlants() {
    if (!this.scene) return
    const { plantFilter, plantMode } = this.settings
    const all = this.allPlants || []
    this.shownPlants = all.filter((plant) => plantFilter === 'all' || (plantFilter === 'planned') === plant.planned)
    this.scene.setPlants(this.shownPlants, plantMode)
    if (this.hasPlantStatusTarget) {
      const planned = all.filter((plant) => plant.planned).length
      this.plantStatusTarget.textContent = all.length
        ? `${all.length} plante${all.length > 1 ? 's' : ''} placée${all.length > 1 ? 's' : ''}, dont ${planned} en projet. ${plantMode === 'mature' ? 'Taille adulte : espèce et conduite, ou saisie sur la fiche.' : ''}`
        : 'Aucune plante placée sur la carte.'
    }
  }

  plantProbe(index) {
    const plant = this.shownPlants?.[index]
    if (!plant) return false
    const source = { plant: 'saisie sur la fiche', species: 'd\'après l\'espèce et la conduite', stratum: 'valeur type de la strate' }[plant.source] || ''
    this.probeTarget.innerHTML = [
      `<p class="font-semibold text-stone-800">${escapeHtml(plant.name || 'Plante')}</p>`,
      plant.species ? `<p>${escapeHtml(plant.species)}</p>` : '',
      `<p>${plant.planned ? 'En projet' : 'En place'} · à maturité ${formatNumber(plant.height, 1)} m de haut, ${formatNumber(plant.spread, 1)} m d'envergure</p>`,
      source ? `<p class="text-stone-400">${source}</p>` : '',
      `<p><a class="font-medium text-forest hover:underline" href="/map?plant=${plant.id}">Ouvrir la fiche</a></p>`,
    ].join('')
    this.probeTarget.classList.remove('hidden')
    return true
  }

  // ---- La pluie -------------------------------------------------------------

  setRain(event) {
    this.settings[event.params.key] = Number(event.params.value)
    this.markChoice(event)
    // Sans occupation du sol, le rythme choisi est celui de toutes les mailles.
    if (event.params.key === 'infiltration' && this.simulation) this.buildSimulations()
    this.simulation?.setOptions(this.simOptions())
    this.baseline?.setOptions(this.simOptions(true))
    this.renderStats()
  }

  // `baseline` : les options du terrain actuel, sans le sol des haies.
  simOptions(baseline = false) {
    const { intensity, duration, infiltration, soilState, rainSource } = this.settings
    const maps = baseline ? this.baseSoilMaps : this.soilMaps
    return {
      intensity, duration, infiltration,
      infiltrationMap: maps?.rate || null,
      storageMap: maps?.storage || null,
      initialFill: SOIL_STATES[soilState] ?? 0.5,
      series: rainSource === 'real' ? this.realRain?.series || [] : null,
    }
  }

  get simFactor() { return this.settings.rainSource === 'real' ? SIM_FACTOR_LONG : SIM_FACTOR }
  get simDt() { return this.settings.rainSource === 'real' ? SIM_DT_LONG : SIM_DT }

  // Ce que le sol boit et peut contenir, par maille de simulation : la
  // moyenne des classes d'occupation du bloc. Sans occupation du sol, le
  // rythme choisi à la main partout et une réserve de 50 mm.
  // Les mailles (1 m) plantées en haie sur courbe.
  hedgeMask() {
    const hedges = this.designs.filter((design) => design.hedge && design.cells)
    if (!hedges.length) return null
    const mask = new Uint8Array(this.full.cols * this.full.rows)
    hedges.forEach((design) => design.cells.forEach((i) => { mask[i] = 1 }))
    return mask
  }

  buildSoilMaps(simCols, simRows, factor, hedges = null) {
    const n = simCols * simRows
    const rate = new Float32Array(n)
    const storage = new Float32Array(n)
    const { cols } = this.full
    for (let r = 0; r < simRows; r++) {
      for (let c = 0; c < simCols; c++) {
        let rateSum = 0
        let storageSum = 0
        for (let dr = 0; dr < factor; dr++) {
          for (let dc = 0; dc < factor; dc++) {
            const i = (r * factor + dr) * cols + c * factor + dc
            const kind = hedges?.[i] ? HEDGE_SOIL
              : this.landcover ? LANDCOVER[this.landcover[i]] || LANDCOVER_UNKNOWN : null
            rateSum += kind ? kind.rate : this.settings.infiltration
            storageSum += kind ? kind.storage : 50
          }
        }
        rate[r * simCols + c] = rateSum / (factor * factor)
        storage[r * simCols + c] = storageSum / (factor * factor)
      }
    }
    return { rate, storage }
  }

  // L'état du sol au départ change la réserve : la pluie repart de zéro.
  setSoilState(event) {
    this.settings.soilState = event.params.value
    this.markChoice(event)
    if (this.simulation) this.buildSimulations()
    this.scene?.clearWater()
  }

  // Averse type (intensité constante) ou pluie réelle (heure par heure) : la
  // grille de simulation change, la pluie repart de zéro.
  async setRainSource(event) {
    this.settings.rainSource = event.params.value
    this.markChoice(event)
    const real = this.settings.rainSource === 'real'
    this.rainTypicalTarget.classList.toggle('hidden', real)
    this.rainRealTarget.classList.toggle('hidden', !real)
    if (real && !this.realRain) await this.loadRealRain()
    if (this.simulation) this.buildSimulations()
    this.scene?.clearWater()
  }

  async setRealPreset(event) {
    this.rainDateTarget.value = event.params.date
    this.settings.realDays = Number(event.params.days)
    this.element.querySelectorAll('[data-choice-group="realDays"] [aria-pressed]').forEach((button) => {
      button.setAttribute('aria-pressed', String(Number(button.dataset.mapReliefValueParam) === this.settings.realDays))
    })
    await this.reloadRealRain()
  }

  async setRealDays(event) {
    this.settings.realDays = Number(event.params.value)
    this.markChoice(event)
    await this.reloadRealRain()
  }

  async reloadRealRain() {
    await this.loadRealRain()
    if (this.simulation) this.buildSimulations()
    this.scene?.clearWater()
  }

  // La pluie heure par heure d'Open-Meteo (gratuit, sans clé) : l'archive
  // (réanalyse ERA5) au-delà d'une semaine, les prévisions récentes sinon.
  async loadRealRain() {
    const start = this.rainDateTarget.value
    const days = this.settings.realDays
    if (!start) return
    const end = new Date(`${start}T12:00:00`)
    end.setDate(end.getDate() + days - 1)
    const endDate = end.toISOString().slice(0, 10)
    const recent = (Date.now() - new Date(`${start}T00:00:00`).valueOf()) / 86400000 < 7
    const host = recent ? 'https://api.open-meteo.com/v1/forecast' : 'https://archive-api.open-meteo.com/v1/archive'
    const url = `${host}?latitude=${SITE.lat}&longitude=${SITE.lng}&start_date=${start}&end_date=${endDate}&hourly=precipitation&timezone=Europe%2FBrussels`
    this.rainRealStatusTarget.textContent = 'Chargement de la pluie mesurée…'
    try {
      const response = await fetch(url)
      const json = await response.json()
      if (!response.ok) throw new Error(json.reason || response.status)
      const series = json.hourly.precipitation.map((v) => v || 0)
      this.realRain = { series, start: json.hourly.time[0], total: series.reduce((a, b) => a + b, 0) }
      this.renderRainChart()
      this.rainRealStatusTarget.textContent = `${formatNumber(this.realRain.total, 1)} mm en ${series.length} h, au plus ${formatNumber(Math.max(...series), 1)} mm/h.`
    } catch (error) {
      this.realRain = { series: [], start: null, total: 0 }
      this.rainRealStatusTarget.textContent = `Pluie indisponible : ${error.message}`
    }
  }

  // L'histogramme de la pluie heure par heure, et le curseur du temps simulé.
  renderRainChart() {
    const series = this.realRain?.series || []
    if (!series.length) { this.rainChartTarget.innerHTML = ''; return }
    const max = Math.max(1, ...series)
    const width = 100 / series.length
    const bars = series.map((v, k) => `<rect x="${k * width}" y="${40 - (v / max) * 40}" width="${Math.max(width * 0.85, 0.3)}" height="${(v / max) * 40}" fill="#0284c7"/>`).join('')
    const time = this.simulation && this.settings.rainSource === 'real' ? this.simulation.time / 3600 : 0
    const cursor = `<line x1="${time * width}" x2="${time * width}" y1="0" y2="40" stroke="#ea580c" stroke-width="0.6"/>`
    this.rainChartTarget.innerHTML = `<svg viewBox="0 0 100 40" preserveAspectRatio="none" class="h-12 w-full rounded bg-stone-50">${bars}${cursor}</svg>`
  }

  // La part du domaine dont le sol est plein : là, la pluie ruisselle.
  saturatedShare(sim) {
    const storage = sim.options.storageMap
    if (!storage) return null
    this.domainWater(sim)
    let full = 0
    for (const i of this.domainCells) if (sim.soil[i] * 1000 >= storage[i] * 0.98) full++
    return this.domainCells.length ? full / this.domainCells.length : 0
  }

  togglePlay() {
    if (!this.scene) return
    if (!this.simulation) this.buildSimulations()
    this.playing = !this.playing
    this.playLabelTarget.textContent = this.playing ? 'Pause' : (this.simulation.time > 0 ? 'Reprendre' : 'Faire pleuvoir')
    this.playButtonTarget.setAttribute('aria-pressed', String(this.playing))
  }

  resetRain() {
    this.playing = false
    this.simulation?.reset()
    this.baseline?.reset()
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
      sim.step(this.simDt)
      this.baseline?.step(this.simDt)
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
      this.rainStateTarget.textContent = this.settings.rainSource === 'real'
        ? `Pluie mesurée : ${formatNumber(this.realRain?.total || 0, 0)} mm en ${this.realRain?.series.length || 0} h`
        : `${this.settings.intensity} mm/h pendant ${formatMinutes(this.settings.duration)}`
      this.statsTarget.innerHTML = ''
      return
    }
    if (this.settings.rainSource === 'real' && this.realRain?.start) {
      const at = new Date(new Date(this.realRain.start).valueOf() + sim.time * 1000)
      const fallen = this.realRain.series.slice(0, Math.floor(sim.time / 3600)).reduce((a, b) => a + b, 0)
      const label = at.toLocaleString('fr-BE', { weekday: 'short', day: 'numeric', month: 'long', hour: '2-digit', minute: '2-digit' })
      this.rainStateTarget.textContent = sim.raining
        ? `${label} : ${formatNumber(sim.intensity, 1)} mm/h, ${formatNumber(fallen, 0)} mm tombés`
        : `Fin de la pluie mesurée (${formatNumber(this.realRain.total, 0)} mm) : l'eau s'écoule`
      this.renderRainChart()
    } else {
      this.rainStateTarget.textContent = sim.raining ? `Il pleut : ${this.settings.intensity} mm/h` : 'La pluie a cessé, l\'eau s\'écoule'
    }
    let deepest = 0
    for (const d of sim.depth) if (d > deepest) deepest = d
    const rows = [
      ['Pluie tombée', sim.rained],
      ['Bue par le sol', sim.infiltrated],
      ['Partie hors de la zone', sim.outflow],
      ['Encore sur le terrain', sim.stored()],
    ]
    const saturated = this.saturatedShare(sim)
    this.statsTarget.innerHTML = rows.map(([label, volume]) => (
      `<div class="flex justify-between gap-2"><dt class="text-stone-500">${label}</dt><dd class="tabular-nums text-stone-800">${formatVolume(volume)}</dd></div>`
    )).join('') + `<div class="flex justify-between gap-2"><dt class="text-stone-500">Lame d'eau la plus profonde</dt><dd class="tabular-nums text-stone-800">${formatDepth(deepest)}</dd></div>` + (saturated == null ? '' : `<div class="flex justify-between gap-2"><dt class="text-stone-500">Sol plein sur le domaine</dt><dd class="tabular-nums text-stone-800">${formatNumber(saturated * 100, 0)} %</dd></div>`)
    this.statsTarget.innerHTML += this.comparisonHtml()
    this.renderDesignList()
  }

  // Les aménagements face au terrain actuel : la même pluie tombe sur les deux
  // reliefs en parallèle, on compare ce qui part, ce qui est bu, ce qui reste.
  comparisonHtml() {
    const sim = this.simulation
    const base = this.baseline
    if (!sim || !base || !this.activeDesigns.length) return ''
    const held = this.designs.reduce((sum, design) => sum + this.designWater(design), 0)
    const kept = this.domainWater(sim)
    const keptBefore = this.domainWater(base)
    const gain = kept - keptBefore
    const percent = keptBefore > 1 ? Math.round((gain / keptBefore) * 100) : 0
    const signed = (volume) => `${volume < 0 ? '−' : '+'}${formatVolume(Math.abs(volume))}`
    const line = (label, value) => `<div class="flex justify-between gap-2"><dt class="text-stone-500">${label}</dt><dd class="tabular-nums font-semibold text-sky-800">${value}</dd></div>`
    return '<div class="mt-2 border-t border-stone-200 pt-2"><p class="mb-1 font-semibold text-stone-700">Avec les aménagements, par rapport au terrain actuel</p>' +
      line('Eau retenue dans les ouvrages', formatVolume(held)) +
      line('Eau gardée sur le domaine', `${signed(gain)} (${percent > 0 ? '+' : ''}${percent} %)`) +
      line('Bue par le sol en plus', signed(sim.infiltrated - base.infiltrated)) +
      '<p class="mt-1 text-stone-400">L\'eau retenue continue de s\'infiltrer après l\'averse : laisse tourner pour voir l\'effet sur le sol.</p></div>'
  }

  // L'eau présente sur l'emprise du domaine (le fond de carte), sans la marge
  // de 150 m autour.
  domainWater(sim) {
    if (!this.domainCells) {
      const bounds = this.domainValue || {}
      if (bounds.west == null) return sim.stored()
      const sw = this.toGrid([bounds.west, bounds.south])
      const ne = this.toGrid([bounds.east, bounds.north])
      const size = sim.cellSize
      const c0 = Math.max(0, Math.floor(sw.x / size))
      const c1 = Math.min(sim.cols - 1, Math.ceil(ne.x / size))
      const r0 = Math.max(0, Math.floor(ne.y / size))
      const r1 = Math.min(sim.rows - 1, Math.ceil(sw.y / size))
      const cells = []
      for (let r = r0; r <= r1; r++) for (let c = c0; c <= c1; c++) cells.push(r * sim.cols + c)
      this.domainCells = cells
    }
    let volume = 0
    for (const i of this.domainCells) volume += sim.depth[i]
    return volume * sim.cellSize * sim.cellSize
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
    this.drawDesigns(context, canvas)
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
      const [r, g, b] = ramp((heights[i] - zMin) / span, HYPSOMETRY)
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
      if (this.tool) this.placeDesign(event)
      else this.probe(event)
    })
  }

  async probe(event) {
    // Une plante sous le clic passe avant le terrain.
    const plantIndex = this.scene.pickPlant(event)
    if (plantIndex != null && this.plantProbe(plantIndex)) return
    const hit = this.scene.pick(event)
    if (!hit) {
      this.probeTarget.classList.add('hidden')
      return
    }
    await this.ensureStation()
    const col = Math.min(this.full.cols - 1, hit.col * this.meshFactor)
    const row = Math.min(this.full.rows - 1, hit.row * this.meshFactor)
    const i = row * this.full.cols + col
    const lines = [`<p class="font-semibold text-stone-800">Altitude ${formatNumber(this.ground[i], 1)} m</p>`]
    if (this.station) {
      const { slope, aspect, wetness, frost } = this.station
      const percent = Math.tan(slope[i]) * 100
      const facing = percent < 2 ? 'à plat' : `pente ${formatNumber(percent)} % tournée ${towards(aspect[i])}`
      lines.push(`<p>Station : ${facing} · sol ${wetnessClass(wetness[i])} · gel ${frostClass(frost[i])} <span class="text-stone-400">(indices)</span></p>`)
    }
    if (this.landcover) {
      const kind = LANDCOVER[this.landcover[i]] || LANDCOVER_UNKNOWN
      lines.push(`<p>Occupation : ${kind.label} — boit ~${kind.rate} mm/h, réserve ~${kind.storage} mm</p>`)
    }
    const above = this.surface ? this.surface[i] - this.full.heights[i] : 0
    if (above > 0.5) lines.push(`<p>Arbre, haie ou toit : ${formatNumber(above, 1)} m au-dessus du sol</p>`)
    if (this.settings.sunMode === 'hours' && this.dayHours) {
      lines.push(`<p>Soleil direct : ${formatHours(this.dayHours.hours[i])} sur ${formatHours(this.dayHours.daylight)} de jour</p>`)
    } else if (this.settings.sunMode === 'instant' && this.lastMask) {
      lines.push(`<p>À ${this.sunHourLabelTarget.textContent} : ${this.lastMask[i] ? 'au soleil' : 'à l\'ombre'}</p>`)
    }
    // L'écoulement réparti dit ce qui arrive vraiment sur une pente ; l'axe
    // unique ne compte que la maille elle-même hors des talwegs.
    const drained = this.station?.spread[i] || this.drainage?.accumulation[i] || 0
    lines.push(`<p>Surface drainée en amont : <span class="tabular-nums">${formatArea(drained)}</span></p>`)
    const hollow = this.drainage?.depression[i] || 0
    if (hollow > 0.05) lines.push(`<p>Dans une cuvette : l'eau peut y monter de ${formatDepth(hollow)}</p>`)
    const sim = this.simulation
    if (sim && sim.time > 0) {
      const sc = Math.min(sim.cols - 1, Math.floor(col / this.simFactor))
      const sr = Math.min(sim.rows - 1, Math.floor(row / this.simFactor))
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

function csrfToken() {
  return document.querySelector('meta[name="csrf-token"]')?.content || ''
}

function escapeHtml(text) {
  return String(text).replace(/[&<>"']/g, (ch) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[ch]))
}

function polygonCenter(geometry) {
  const ring = geometry?.coordinates?.[0]
  if (!ring?.length) return null
  const points = ring.slice(0, -1)
  return [points.reduce((s, p) => s + p[0], 0) / points.length, points.reduce((s, p) => s + p[1], 0) / points.length]
}

function heightFromGrid(heights, cols, rows, cell, { x, y }) {
  const c = Math.min(cols - 1, Math.max(0, Math.round(x / cell)))
  const r = Math.min(rows - 1, Math.max(0, Math.round(y / cell)))
  return heights[r * cols + c]
}

function nextPaint() {
  return new Promise((resolve) => setTimeout(resolve, 30))
}

function toMercator(lat, lng) {
  const radius = 6378137
  return [radius * (lng * Math.PI) / 180, radius * Math.log(Math.tan(Math.PI / 4 + (lat * Math.PI) / 360))]
}

function ramp(t, stops) {
  const x = Math.min(1, Math.max(0, t))
  for (let k = 1; k < stops.length; k++) {
    const [t1, c1] = stops[k]
    const [t0, c0] = stops[k - 1]
    if (x <= t1) {
      const f = (x - t0) / (t1 - t0)
      return c0.map((v, j) => Math.round(v + (c1[j] - v) * f))
    }
  }
  return stops[stops.length - 1][1]
}

function formatHours(hours) {
  const total = Math.round(hours * 4) * 15
  const h = Math.floor(total / 60)
  const m = total % 60
  return m ? `${h} h ${String(m).padStart(2, '0')}` : `${h} h`
}

// L'azimut en mots : « au sud », « à l'ouest »…
function compass(azimuth) {
  const names = ['au nord', 'au nord-est', 'à l\'est', 'au sud-est', 'au sud', 'au sud-ouest', 'à l\'ouest', 'au nord-ouest']
  return names[Math.round(azimuth / (Math.PI / 4)) % 8]
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
