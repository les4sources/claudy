// La scène 3D du relief (`/map/relief`) : le MNT du domaine en maillage, drapé
// de l'ortho ou d'une teinte d'altitude, avec courbes de niveau, axes
// d'écoulement, cuvettes et objets de la carte en surimpression, et l'eau de la
// simulation (lame d'eau teintée sur le terrain + traceurs qui suivent le
// courant), et le soleil (ombres à une heure donnée ou heures de soleil sur la
// journée, teintées sur le terrain, avec la lumière de la scène à sa place).
//
// Ce module (et la Niva qu'il embarque) est le SEUL à importer three.js, et le
// contrôleur Stimulus le charge en `import()` dynamique : les autres pages ne
// paient pas ses 600 Ko.
//
// Repère : x vers l'est, z vers le sud, y vers le haut, en mètres, centré sur
// la grille. Le terrain, l'eau et les traceurs vivent dans un même groupe dont
// l'échelle verticale EST l'exagération : la changer ne recalcule rien.

import * as THREE from 'three'
import { OrbitControls } from 'three/addons/controls/OrbitControls.js'
import { NIVA, buildNivaModel, setNivaLights } from './map_relief_niva'

// La conduite passe par ce module : le contrôleur ne charge three.js qu'ici.
export { createNivaState, stepNiva } from './map_relief_niva'

const OVERLAY_SCALE = 2
const PARTICLES = 5000

export class ReliefScene {
  // `grid` : { heights (Float32Array, m), cols, rows, cellSize, zBase }
  constructor(container, grid) {
    this.container = container
    this.grid = grid
    this.exaggeration = 2.5
    this.particlesOn = true

    this.renderer = new THREE.WebGLRenderer({ antialias: true })
    this.renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, 2))
    this.renderer.outputColorSpace = THREE.SRGBColorSpace
    container.appendChild(this.renderer.domElement)
    this.renderer.domElement.classList.add('block', 'h-full', 'w-full', 'touch-none')

    this.scene = new THREE.Scene()
    this.scene.background = new THREE.Color('#dfe9ee')
    this.world = new THREE.Group()
    this.scene.add(this.world)

    const width = (grid.cols - 1) * grid.cellSize
    const depth = (grid.rows - 1) * grid.cellSize
    this.size = { width, depth }
    this.camera = new THREE.PerspectiveCamera(40, 1, 5, width * 8)
    this.controls = new OrbitControls(this.camera, this.renderer.domElement)
    this.controls.enableDamping = true
    this.controls.maxPolarAngle = Math.PI * 0.47
    this.controls.minDistance = 30
    this.controls.maxDistance = width * 3

    // Le soleil vient du nord-ouest, comme sur tous les ombrages de relief :
    // c'est la convention que l'œil lit comme « en creux / en bosse ».
    this.night = false
    this.sunIntensity = 1.9
    this.hemiLight = new THREE.HemisphereLight('#f4f7fb', '#5b5140', 1.1)
    this.scene.add(this.hemiLight)
    this.sunLight = new THREE.DirectionalLight('#fffaf0', 1.9)
    this.scene.add(this.sunLight)
    this.setSun(null)

    this.buildTerrain()
    this.buildParticles()
    this.buildPlants()
    this.buildBeacon()
    this.resetView()

    this.resizeObserver = new ResizeObserver(() => this.resize())
    this.resizeObserver.observe(container)
    this.resize()

    this.onFrame = null
    this.renderer.setAnimationLoop(() => this.frame())
  }

  // Le maillage : un sommet par maille du MNT, deux triangles par carré.
  buildTerrain() {
    const { heights, cols, rows, cellSize, zBase } = this.grid
    const count = cols * rows
    const positions = new Float32Array(count * 3)
    const uvs = new Float32Array(count * 2)
    const elevation = new Float32Array(count)
    const x0 = ((cols - 1) * cellSize) / 2
    const z0 = ((rows - 1) * cellSize) / 2
    for (let r = 0; r < rows; r++) {
      for (let c = 0; c < cols; c++) {
        const i = r * cols + c
        positions[i * 3] = c * cellSize - x0
        positions[i * 3 + 1] = heights[i] - zBase
        positions[i * 3 + 2] = r * cellSize - z0
        uvs[i * 2] = c / (cols - 1)
        uvs[i * 2 + 1] = 1 - r / (rows - 1)
        elevation[i] = heights[i]
      }
    }
    const indices = new Uint32Array((cols - 1) * (rows - 1) * 6)
    let k = 0
    for (let r = 0; r < rows - 1; r++) {
      for (let c = 0; c < cols - 1; c++) {
        const a = r * cols + c
        const b = a + 1
        const d = a + cols
        const e = d + 1
        indices[k++] = a; indices[k++] = d; indices[k++] = b
        indices[k++] = b; indices[k++] = d; indices[k++] = e
      }
    }
    const geometry = new THREE.BufferGeometry()
    geometry.setAttribute('position', new THREE.BufferAttribute(positions, 3))
    geometry.setAttribute('uv', new THREE.BufferAttribute(uvs, 2))
    geometry.setAttribute('elevation', new THREE.BufferAttribute(elevation, 1))
    geometry.setIndex(new THREE.BufferAttribute(indices, 1))
    geometry.computeVertexNormals()
    geometry.computeBoundingSphere()

    // Les surimpressions (axes, cuvettes, objets) : une toile à 2× la grille.
    this.overlayCanvas = document.createElement('canvas')
    this.overlayCanvas.width = cols * OVERLAY_SCALE
    this.overlayCanvas.height = rows * OVERLAY_SCALE
    this.overlayTexture = new THREE.CanvasTexture(this.overlayCanvas)
    this.overlayTexture.colorSpace = THREE.SRGBColorSpace
    this.overlayTexture.anisotropy = 4

    // L'eau : une texture RGBA à la résolution de la simulation, remplie à
    // chaque image par `updateWater`.
    this.waterData = new Uint8Array(4)
    this.waterTexture = new THREE.DataTexture(this.waterData, 1, 1)
    this.waterTexture.needsUpdate = true
    // Le soleil : même principe, à la résolution du MNT (ombres ou heures).
    this.sunData = new Uint8Array(4)
    this.sunTexture = new THREE.DataTexture(this.sunData, 1, 1)
    this.sunTexture.needsUpdate = true

    this.uniforms = {
      uContour: { value: 5 },
      uOverlay: { value: this.overlayTexture },
      uWater: { value: this.waterTexture },
      uSun: { value: this.sunTexture },
    }
    const placeholder = new THREE.DataTexture(new Uint8Array([200, 200, 190, 255]), 1, 1)
    placeholder.needsUpdate = true
    this.material = new THREE.MeshStandardMaterial({ map: placeholder, roughness: 1, metalness: 0 })
    this.material.onBeforeCompile = (shader) => {
      Object.assign(shader.uniforms, this.uniforms)
      shader.vertexShader = shader.vertexShader
        .replace('#include <common>', '#include <common>\nattribute float elevation;\nvarying float vElevation;\nvarying vec2 vGridUv;')
        .replace('#include <begin_vertex>', '#include <begin_vertex>\nvElevation = elevation;\nvGridUv = uv;')
      shader.fragmentShader = shader.fragmentShader
        .replace('#include <common>', `#include <common>
uniform float uContour;
uniform sampler2D uOverlay;
uniform sampler2D uWater;
uniform sampler2D uSun;
varying float vElevation;
varying vec2 vGridUv;
float contourLine(float value, float width) {
  float f = abs(fract(value - 0.5) - 0.5) / max(fwidth(value), 1e-5);
  return 1.0 - min(f / width, 1.0);
}`)
        .replace('#include <map_fragment>', `#include <map_fragment>
vec4 sunTint = texture2D(uSun, vGridUv);
diffuseColor.rgb = mix(diffuseColor.rgb, sunTint.rgb, sunTint.a);
vec4 water = texture2D(uWater, vGridUv);
diffuseColor.rgb = mix(diffuseColor.rgb, water.rgb, water.a);
if (uContour > 0.0) {
  float minor = contourLine(vElevation / uContour, 0.9);
  float major = contourLine(vElevation / (uContour * 5.0), 1.6);
  float line = max(minor * 0.35, major * 0.7);
  diffuseColor.rgb = mix(diffuseColor.rgb, vec3(0.28, 0.2, 0.12), line);
}
vec4 overlay = texture2D(uOverlay, vGridUv);
diffuseColor.rgb = mix(diffuseColor.rgb, overlay.rgb, overlay.a);`)
    }
    this.terrain = new THREE.Mesh(geometry, this.material)
    this.world.add(this.terrain)
  }

  buildParticles() {
    this.particlePositions = new Float32Array(PARTICLES * 3)
    this.particleAge = new Float32Array(PARTICLES)
    const geometry = new THREE.BufferGeometry()
    geometry.setAttribute('position', new THREE.BufferAttribute(this.particlePositions, 3))
    geometry.setDrawRange(0, 0)
    this.particles = new THREE.Points(geometry, new THREE.PointsMaterial({
      color: '#e0f2fe', size: 2.5, sizeAttenuation: false, transparent: true, opacity: 0.9,
    }))
    this.particles.frustumCulled = false
    this.world.add(this.particles)
    this.particleCount = 0
  }

  setBaseTexture(texture) {
    texture.colorSpace = THREE.SRGBColorSpace
    texture.anisotropy = this.renderer.capabilities.getMaxAnisotropy()
    this.material.map = texture
    this.material.needsUpdate = true
  }

  loadImageTexture(url) {
    return new THREE.TextureLoader().loadAsync(url)
  }

  canvasTexture(canvas) {
    return new THREE.CanvasTexture(canvas)
  }

  setExaggeration(value) {
    this.exaggeration = value
    this.world.scale.y = value
    // Les plantes et la balise gardent leur vraie hauteur sur un relief exagéré.
    if (this.plants?.length) this.layoutPlants()
    if (this.beacon) this.beacon.scale.y = 1 / value
  }

  // ---- Les plantes nourricières ---------------------------------------------
  //
  // Un tronc et un houppier par plante, en instances (une centaine de plantes
  // = deux appels de dessin). Les plantes en projet (« Sur plan »…) sont
  // translucides, les autres pleines. En mode « repères », un simple cône.
  buildPlants() {
    const max = 2000
    const trunkGeometry = new THREE.CylinderGeometry(0.5, 0.5, 1, 6)
    trunkGeometry.translate(0, 0.5, 0)
    const crownGeometry = new THREE.SphereGeometry(0.5, 14, 10)
    const markerGeometry = new THREE.ConeGeometry(0.5, 1, 8)
    markerGeometry.rotateX(Math.PI)
    markerGeometry.translate(0, 0.5, 0)
    const solid = (color) => new THREE.MeshStandardMaterial({ color, roughness: 0.9 })
    const ghost = (color) => new THREE.MeshStandardMaterial({ color, roughness: 0.9, transparent: true, opacity: 0.5, depthWrite: false })
    this.plantMeshes = {
      trunk: new THREE.InstancedMesh(trunkGeometry, solid('#6b4f2a'), max),
      trunkPlanned: new THREE.InstancedMesh(trunkGeometry, ghost('#a8865a'), max),
      crown: new THREE.InstancedMesh(crownGeometry, solid('#2f7d32'), max),
      crownPlanned: new THREE.InstancedMesh(crownGeometry, ghost('#86efac'), max),
      marker: new THREE.InstancedMesh(markerGeometry, solid('#16a34a'), max),
      markerPlanned: new THREE.InstancedMesh(markerGeometry, solid('#f59e0b'), max),
    }
    Object.values(this.plantMeshes).forEach((mesh) => {
      mesh.count = 0
      mesh.frustumCulled = false
      this.world.add(mesh)
    })
    this.plants = []
    this.plantMode = 'off'
  }

  // `plants` : [{ x, z (m, depuis le coin nord-ouest), ground (m), height,
  // spread, stratum, planned }] ; `mode` : off | markers | mature.
  setPlants(plants, mode) {
    this.plants = plants
    this.plantMode = mode
    this.layoutPlants()
  }

  layoutPlants() {
    const meshes = this.plantMeshes
    const counts = { trunk: 0, trunkPlanned: 0, crown: 0, crownPlanned: 0, marker: 0, markerPlanned: 0 }
    const m = new THREE.Matrix4()
    const q = new THREE.Quaternion()
    const exaggeration = this.exaggeration
    const g = this.grid
    const x0 = ((g.cols - 1) * g.cellSize) / 2
    const z0 = ((g.rows - 1) * g.cellSize) / 2
    const put = (key, x, y, z, sx, sy, sz) => {
      // L'échelle verticale du monde vaut l'exagération : on la défait.
      m.compose(new THREE.Vector3(x - x0, y, z - z0), q, new THREE.Vector3(sx, sy / exaggeration, sz))
      meshes[key].setMatrixAt(counts[key]++, m)
    }
    this.plantIndex = { crown: [], crownPlanned: [], marker: [], markerPlanned: [] }
    if (this.plantMode !== 'off') {
      this.plants.forEach((plant, index) => {
        const base = plant.ground - g.zBase
        const suffix = plant.planned ? 'Planned' : ''
        if (this.plantMode === 'markers') {
          this.plantIndex[`marker${suffix}`].push(index)
          put(`marker${suffix}`, plant.x, base, plant.z, 1.4, 2.5, 1.4)
          return
        }
        const { height, spread } = plant
        // La silhouette selon la conduite : une cépée part du sol, une trogne
        // porte sa tête sur un tronc court, un arbre libre sur un tronc d'un
        // tiers de sa hauteur.
        let trunk = height * 0.35
        if (plant.stratum === 'coppice' || ['shrub', 'subshrub', 'herbaceous', 'groundcover', 'aquatic'].includes(plant.stratum)) trunk = 0
        if (plant.stratum === 'pollard' || plant.stratum === 'food_pollard') trunk = Math.min(2.5, height * 0.55)
        const crown = Math.max(0.3, height - trunk)
        if (trunk > 0) put(`trunk${suffix}`, plant.x, base, plant.z, Math.max(0.25, spread * 0.06), trunk + crown * 0.3, Math.max(0.25, spread * 0.06))
        this.plantIndex[`crown${suffix}`].push(index)
        put(`crown${suffix}`, plant.x, base + (trunk + crown / 2) / exaggeration, plant.z, spread, crown, spread)
      })
    }
    Object.entries(counts).forEach(([key, count]) => {
      meshes[key].count = count
      meshes[key].instanceMatrix.needsUpdate = true
    })
  }

  // La plante sous un clic : son indice dans la liste donnée à `setPlants`.
  pickPlant(event) {
    if (this.plantMode === 'off' || !this.plants.length) return null
    const rect = this.renderer.domElement.getBoundingClientRect()
    const pointer = new THREE.Vector2(((event.clientX - rect.left) / rect.width) * 2 - 1, -((event.clientY - rect.top) / rect.height) * 2 + 1)
    const raycaster = new THREE.Raycaster()
    raycaster.setFromCamera(pointer, this.camera)
    const keys = Object.keys(this.plantIndex)
    const hits = raycaster.intersectObjects(keys.map((key) => this.plantMeshes[key]), false)
    const hit = hits[0]
    if (!hit) return null
    const key = keys.find((k) => this.plantMeshes[k] === hit.object)
    return this.plantIndex[key][hit.instanceId] ?? null
  }

  // ---- La balise du survol ----------------------------------------------------
  //
  // Un faisceau et un anneau qui pulsent au-dessus de l'aménagement survolé dans
  // la liste : on le retrouve d'un coup d'œil, même masqué ou hors champ.
  buildBeacon() {
    const beacon = new THREE.Group()
    const beam = new THREE.Mesh(
      new THREE.CylinderGeometry(1.2, 1.2, 60, 16, 1, true).translate(0, 30, 0),
      new THREE.MeshBasicMaterial({ color: '#facc15', transparent: true, opacity: 0.35, depthWrite: false, side: THREE.DoubleSide }),
    )
    const ring = new THREE.Mesh(
      new THREE.RingGeometry(4, 6, 40).rotateX(-Math.PI / 2),
      new THREE.MeshBasicMaterial({ color: '#facc15', transparent: true, opacity: 0.8, depthWrite: false, side: THREE.DoubleSide }),
    )
    beacon.add(beam, ring)
    beacon.visible = false
    this.beaconRing = ring
    this.beaconBeam = beam
    this.beacon = beacon
    this.world.add(beacon)
  }

  // `point` : { x, z, ground, size } en mètres (coin nord-ouest), ou null.
  setBeacon(point) {
    if (!point) { this.beacon.visible = false; return }
    const g = this.grid
    const x0 = ((g.cols - 1) * g.cellSize) / 2
    const z0 = ((g.rows - 1) * g.cellSize) / 2
    this.beacon.position.set(point.x - x0, point.ground - g.zBase, point.z - z0)
    this.beacon.scale.set(1, 1 / this.exaggeration, 1)
    this.beaconSize = Math.max(6, point.size || 6)
    this.beacon.visible = true
  }

  animateBeacon(time) {
    if (!this.beacon?.visible) return
    const pulse = (Math.sin(time / 220) + 1) / 2
    const size = this.beaconSize / 5 * (0.8 + pulse * 0.5)
    this.beaconRing.scale.set(size, 1, size)
    this.beaconRing.material.opacity = 0.45 + pulse * 0.5
    this.beaconBeam.material.opacity = 0.18 + pulse * 0.25
  }

  // Remplace les hauteurs du maillage (terrain nu ↔ arbres et toits) sans
  // reconstruire la géométrie.
  setHeights(heights) {
    const { zBase } = this.grid
    const geometry = this.terrain.geometry
    const positions = geometry.attributes.position.array
    const elevation = geometry.attributes.elevation.array
    for (let i = 0; i < heights.length; i++) {
      positions[i * 3 + 1] = heights[i] - zBase
      elevation[i] = heights[i]
    }
    geometry.attributes.position.needsUpdate = true
    geometry.attributes.elevation.needsUpdate = true
    geometry.computeVertexNormals()
    geometry.computeBoundingSphere()
  }

  // La lumière de la scène vient du vrai soleil (`{ azimuth, altitude }`,
  // azimut depuis le nord) ; sans soleil, du nord-ouest, la convention des
  // ombrages de relief.
  setSun(sun) {
    const distance = this.size.width * 1.5
    if (!sun || sun.altitude <= 0) {
      this.sunLight.position.set(-this.size.width, this.size.width * 0.9, -this.size.depth)
      this.sunIntensity = 1.9
      return this.applyLighting()
    }
    const horizontal = Math.cos(sun.altitude) * distance
    this.sunLight.position.set(Math.sin(sun.azimuth) * horizontal, Math.sin(sun.altitude) * distance,
                               -Math.cos(sun.azimuth) * horizontal)
    this.sunIntensity = 2.2
    this.applyLighting()
  }

  // Une teinte RGBA par maille du MNT (lignes du nord au sud), posée sur le
  // terrain : ombres ou heures de soleil. `null` l'efface.
  setSunTint(rgba, cols, rows) {
    if (!rgba) {
      this.sunData.fill(0)
      this.sunTexture.needsUpdate = true
      return
    }
    if (this.sunTexture.image.width !== cols || this.sunTexture.image.height !== rows) {
      this.sunTexture.dispose()
      this.sunData = new Uint8Array(cols * rows * 4)
      this.sunTexture = new THREE.DataTexture(this.sunData, cols, rows)
      this.sunTexture.magFilter = THREE.LinearFilter
      this.sunTexture.minFilter = THREE.LinearFilter
      this.sunTexture.colorSpace = THREE.SRGBColorSpace
      this.uniforms.uSun.value = this.sunTexture
    }
    // Une DataTexture se lit de bas en haut : la ligne nord va en dernier.
    for (let r = 0; r < rows; r++) {
      this.sunData.set(rgba.subarray(r * cols * 4, (r + 1) * cols * 4), (rows - 1 - r) * cols * 4)
    }
    this.sunTexture.needsUpdate = true
  }

  setContourInterval(meters) {
    this.uniforms.uContour.value = meters
  }

  refreshOverlay() {
    this.overlayTexture.needsUpdate = true
  }

  // Vue de départ : trois quarts depuis le sud-ouest, le domaine au centre.
  resetView() {
    const { width, depth } = this.size
    this.setExaggeration(this.exaggeration)
    this.controls.target.set(0, (this.grid.zMid - this.grid.zBase) * this.exaggeration * 0.6, 0)
    this.camera.position.set(-width * 0.42, width * 0.68, depth * 1.05)
    this.controls.update()
  }

  resize() {
    const { clientWidth, clientHeight } = this.container
    if (!clientWidth || !clientHeight) return
    this.renderer.setSize(clientWidth, clientHeight, false)
    this.camera.aspect = clientWidth / clientHeight
    this.camera.updateProjectionMatrix()
  }

  // La lame d'eau de la simulation en couleurs : un film d'un millimètre à
  // peine teinté, un filet de quelques centimètres bleu clair, une mare bleu
  // profond. L'échelle est logarithmique : de 1 mm à 1 m, tout se voit.
  //
  // La lame affichée est lissée sur 3 × 3 mailles et son opacité monte
  // progressivement : sur un film mince, le modèle à tuyaux mouille une maille
  // sur deux d'un pas à l'autre, et un seuil sec dessinait un damier.
  updateWater(sim) {
    const { cols, rows } = sim
    const depth = this.smoothedDepth(sim)
    if (this.waterTexture.image.width !== cols || this.waterTexture.image.height !== rows) {
      this.waterTexture.dispose()
      this.waterData = new Uint8Array(cols * rows * 4)
      this.waterTexture = new THREE.DataTexture(this.waterData, cols, rows)
      this.waterTexture.magFilter = THREE.LinearFilter
      this.waterTexture.minFilter = THREE.LinearFilter
      this.waterTexture.colorSpace = THREE.SRGBColorSpace
      this.uniforms.uWater.value = this.waterTexture
    }
    const data = this.waterData
    for (let r = 0; r < rows; r++) {
      // Une DataTexture se lit de bas en haut : la ligne nord va en dernier.
      const out = (rows - 1 - r) * cols
      for (let c = 0; c < cols; c++) {
        const d = depth[r * cols + c]
        const o = (out + c) * 4
        if (d < 0.0005) { data[o + 3] = 0; continue }
        const t = Math.max(0, Math.min(1, Math.log10(d * 1000) / 3))
        const fade = Math.min(1, (d - 0.0005) / 0.004)
        data[o] = 150 - 130 * t
        data[o + 1] = 215 - 125 * t
        data[o + 2] = 250 - 60 * t
        data[o + 3] = (70 + 170 * t) * fade
      }
    }
    this.waterTexture.needsUpdate = true
  }

  smoothedDepth(sim) {
    const { cols, rows, depth } = sim
    if (this.smoothed?.length !== depth.length) this.smoothed = new Float32Array(depth.length)
    const out = this.smoothed
    for (let r = 0; r < rows; r++) {
      const r0 = r > 0 ? r - 1 : r
      const r1 = r + 1 < rows ? r + 1 : r
      for (let c = 0; c < cols; c++) {
        const c0 = c > 0 ? c - 1 : c
        const c1 = c + 1 < cols ? c + 1 : c
        let sum = 0
        let n = 0
        for (let rr = r0; rr <= r1; rr++) {
          for (let cc = c0; cc <= c1; cc++) { sum += depth[rr * cols + cc]; n++ }
        }
        // La maille elle-même compte double : une mare garde son bord net.
        const own = depth[r * cols + c]
        out[r * cols + c] = (sum + own) / (n + 1)
      }
    }
    return out
  }

  clearWater() {
    this.waterData.fill(0)
    this.waterTexture.needsUpdate = true
    this.particleCount = 0
    this.particles.geometry.setDrawRange(0, 0)
  }

  // Les traceurs suivent la vitesse de l'eau (grille de simulation). Ils
  // naissent dans une maille mouillée tirée au hasard, meurent au sec, hors de
  // la grille ou après ~4 s. Leur vitesse à l'écran est proportionnelle au
  // courant, pas au temps simulé : un courant de 1 m/s avance de 0,6 m par
  // image, lisible quelle que soit la vitesse de la simulation.
  updateParticles(sim) {
    if (!this.particlesOn) {
      this.particles.geometry.setDrawRange(0, 0)
      return
    }
    const { cols, rows, depth, velX, velY, cellSize } = sim
    const g = this.grid
    const x0 = ((g.cols - 1) * g.cellSize) / 2
    const z0 = ((g.rows - 1) * g.cellSize) / 2
    const pos = this.particlePositions
    const wetFloor = 0.002
    let spawnTries = 0
    for (let p = 0; p < PARTICLES; p++) {
      let x = pos[p * 3] + x0
      let z = pos[p * 3 + 2] + z0
      let c = Math.floor(x / cellSize)
      let r = Math.floor(z / cellSize)
      let alive = this.particleAge[p] > 0 && c >= 0 && r >= 0 && c < cols && r < rows && depth[r * cols + c] > wetFloor
      if (!alive) {
        this.particleAge[p] = 0
        if (spawnTries > 4000) { pos[p * 3 + 1] = -1e6; continue }
        let found = false
        for (let t = 0; t < 8 && !found; t++) {
          spawnTries++
          const i = Math.floor(Math.random() * cols * rows)
          if (depth[i] > wetFloor * 2) {
            c = i % cols
            r = (i - c) / cols
            x = (c + Math.random()) * cellSize
            z = (r + Math.random()) * cellSize
            this.particleAge[p] = 200 + Math.random() * 60
            found = true
          }
        }
        if (!found) { pos[p * 3 + 1] = -1e6; continue }
      }
      const i = r * cols + c
      const vx = velX[i]
      const vz = velY[i]
      const speed = Math.hypot(vx, vz)
      const stepLength = Math.min(speed, 3) * 0.6
      if (speed > 1e-6) {
        x += (vx / speed) * stepLength
        z += (vz / speed) * stepLength
      }
      this.particleAge[p] -= 1
      pos[p * 3] = x - x0
      pos[p * 3 + 2] = z - z0
      pos[p * 3 + 1] = this.heightAt(x, z) - g.zBase + depth[i] + 0.15 / this.exaggeration
    }
    this.particleCount = PARTICLES
    this.particles.geometry.setDrawRange(0, PARTICLES)
    this.particles.geometry.attributes.position.needsUpdate = true
  }

  // ---- La nuit -------------------------------------------------------------
  //
  // Un ciel bleu nuit étoilé, une brume qui avale le lointain, une lune
  // froide : le terrain ne se voit plus guère que dans les phares.
  setNight(on) {
    this.night = on
    this.scene.background.set(on ? '#0a1220' : '#dfe9ee')
    this.scene.fog = on ? new THREE.FogExp2('#0a1220', 0.0016) : null
    if (on && !this.stars) this.buildStars()
    if (this.stars) this.stars.visible = on
    this.applyLighting()
    if (this.niva) this.setNivaLights(this.nivaLights)
  }

  applyLighting() {
    this.hemiLight.intensity = this.night ? 0.07 : 1.1
    this.hemiLight.color.set(this.night ? '#8fa6d6' : '#f4f7fb')
    this.sunLight.intensity = this.night ? 0.14 : this.sunIntensity
    this.sunLight.color.set(this.night ? '#9db4ff' : '#fffaf0')
  }

  buildStars() {
    const count = 1500
    const radius = this.size.width * 3
    const positions = new Float32Array(count * 3)
    for (let i = 0; i < count; i++) {
      const azimuth = Math.random() * Math.PI * 2
      const height = 0.08 + Math.random() * 0.92
      const ring = Math.sqrt(1 - height * height)
      positions.set([Math.cos(azimuth) * ring * radius, height * radius, Math.sin(azimuth) * ring * radius], i * 3)
    }
    const geometry = new THREE.BufferGeometry()
    geometry.setAttribute('position', new THREE.BufferAttribute(positions, 3))
    this.stars = new THREE.Points(geometry, new THREE.PointsMaterial({
      color: '#dbe4ff', size: 1.6, sizeAttenuation: false, transparent: true, opacity: 0.85, fog: false,
    }))
    this.stars.frustumCulled = false
    this.scene.add(this.stars)
  }

  // ---- La Niva ---------------------------------------------------------------
  //
  // La voiture vit hors du groupe exagéré : elle garde sa vraie taille, posée
  // à la hauteur du relief exagéré et inclinée sur sa pente exagérée, pour
  // coller au terrain qu'on voit. La caméra la suit (« poursuite ») ou tourne
  // autour d'elle à la souris (« libre »).
  showNiva(on) {
    if (on) {
      this.niva ||= buildNivaModel()
      this.scene.add(this.niva)
      this.nivaLights ||= { low: false, bar: false }
      this.setNivaLights(this.nivaLights)
      this.camera.near = 0.3
      this.controls.minDistance = 4
      this.chaseDistance ||= 14
      this.setCameraMode(this.cameraMode || 'chase')
      if (!this.onWheel) {
        this.onWheel = (event) => {
          if (this.cameraMode !== 'chase' || !this.niva?.parent) return
          event.preventDefault()
          this.chaseDistance = Math.min(80, Math.max(6, this.chaseDistance * (event.deltaY > 0 ? 1.12 : 0.89)))
        }
        this.renderer.domElement.addEventListener('wheel', this.onWheel, { passive: false })
      }
    } else if (this.niva) {
      this.scene.remove(this.niva)
      this.camera.near = 5
      this.controls.minDistance = 30
      this.controls.enabled = true
    }
    this.camera.updateProjectionMatrix()
  }

  setCameraMode(mode) {
    this.cameraMode = mode
    this.controls.enabled = mode !== 'chase'
    this.lastNivaTarget = null
  }

  // `lights` : { low (phares), bar (pare-buffle et rampe de toit) }.
  setNivaLights(lights) {
    this.nivaLights = lights
    if (this.niva) setNivaLights(this.niva, { ...lights, night: this.night, braking: this.nivaBraking })
  }

  // `state` : l'état de la conduite (`stepNiva`), en mètres depuis le coin
  // nord-ouest et en altitudes vraies.
  updateNiva(state, dt) {
    const model = this.niva
    if (!model?.parent || !state.wheels) return
    const g = this.grid
    const x0 = ((g.cols - 1) * g.cellSize) / 2
    const z0 = ((g.rows - 1) * g.cellSize) / 2
    const ex = this.exaggeration
    const [fl, fr, rl, rr] = state.wheels
    const forward = new THREE.Vector3(Math.sin(state.heading), 0, -Math.cos(state.heading))
    const along = forward.clone().multiplyScalar(NIVA.wheelbase).setY(((fl + fr) - (rl + rr)) / 2 * ex).normalize()
    const left = new THREE.Vector3(-Math.cos(state.heading), 0, -Math.sin(state.heading))
      .multiplyScalar(NIVA.track).setY(((fl + rl) - (fr + rr)) / 2 * ex).normalize()
    const up = new THREE.Vector3().crossVectors(along, left).normalize()
    left.crossVectors(up, along).normalize()
    model.quaternion.setFromRotationMatrix(new THREE.Matrix4().makeBasis(left, up, along))
    model.position.set(state.x - x0, (state.ground - g.zBase) * ex, state.z - z0)

    const { wheels, steering } = model.userData
    for (const wheel of wheels) wheel.rotation.x = state.wheelSpin
    for (const pivot of steering) pivot.rotation.y = -state.steer
    if (state.braking !== this.nivaBraking) {
      this.nivaBraking = state.braking
      this.setNivaLights(this.nivaLights)
    }

    const target = model.position.clone().add(new THREE.Vector3(0, 1.4, 0))
    if (this.cameraMode === 'chase') {
      const desired = target.clone().addScaledVector(forward, -this.chaseDistance)
      desired.y += this.chaseDistance * 0.38
      // Jamais sous le terrain, même derrière une butte.
      const ground = (this.heightAt(desired.x + x0, desired.z + z0) - g.zBase) * ex + 1.5
      if (desired.y < ground) desired.y = ground
      const k = this.lastNivaTarget ? 1 - Math.exp(-dt * 4) : 1
      this.camera.position.lerp(desired, k)
      this.controls.target.lerp(target.clone().addScaledVector(forward, 4), Math.min(1, k * 2))
    } else if (this.lastNivaTarget) {
      const delta = target.clone().sub(this.lastNivaTarget)
      this.camera.position.add(delta)
      this.controls.target.add(delta)
    } else {
      this.controls.target.copy(target)
    }
    this.lastNivaTarget = target
  }

  // L'altitude (m) sous un point du repère local (x vers l'est, z vers le sud,
  // origine au coin nord-ouest), au plus proche sommet du MNT.
  heightAt(x, z) {
    const g = this.grid
    const c = Math.min(g.cols - 1, Math.max(0, Math.round(x / g.cellSize)))
    const r = Math.min(g.rows - 1, Math.max(0, Math.round(z / g.cellSize)))
    return g.heights[r * g.cols + c]
  }

  // Le point du terrain sous un clic : { col, row } de la grille du MNT, ou nul.
  pick(event) {
    const rect = this.renderer.domElement.getBoundingClientRect()
    const pointer = new THREE.Vector2(
      ((event.clientX - rect.left) / rect.width) * 2 - 1,
      -((event.clientY - rect.top) / rect.height) * 2 + 1,
    )
    const raycaster = new THREE.Raycaster()
    raycaster.setFromCamera(pointer, this.camera)
    const hit = raycaster.intersectObject(this.terrain, false)[0]
    if (!hit?.uv) return null
    const g = this.grid
    return { col: Math.round(hit.uv.x * (g.cols - 1)), row: Math.round((1 - hit.uv.y) * (g.rows - 1)) }
  }

  frame() {
    this.onFrame?.()
    this.animateBeacon(performance.now())
    this.controls.update()
    this.renderer.render(this.scene, this.camera)
  }

  dispose() {
    this.renderer.setAnimationLoop(null)
    this.resizeObserver.disconnect()
    this.controls.dispose()
    if (this.onWheel) this.renderer.domElement.removeEventListener('wheel', this.onWheel)
    this.terrain.geometry.dispose()
    this.material.dispose()
    this.particles.geometry.dispose()
    this.overlayTexture.dispose()
    this.waterTexture.dispose()
    this.sunTexture.dispose()
    this.renderer.dispose()
    this.renderer.domElement.remove()
  }
}
