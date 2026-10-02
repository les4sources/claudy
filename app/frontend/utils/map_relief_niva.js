// La Niva du domaine sur la vue 3D (`/map/relief`) : une Lada Niva verte mate,
// pare-buffle à barre LED et rampe de toit, qu'on pose sur le terrain et qu'on
// conduit aux flèches.
//
// Deux moitiés :
// - `stepNiva` — la conduite, sans three.js : vitesse, direction, pente, dévers
//   et obstacles, lus sur le VRAI relief (mètres, sans exagération) ;
// - `buildNivaModel` — la voiture en primitives three.js, ses phares et ses
//   faisceaux, que la scène pose et incline sur le relief exagéré.
//
// Repère de la conduite : x vers l'est et z vers le sud, en mètres depuis le
// coin nord-ouest de la grille ; `heading` est l'azimut depuis le nord, dans le
// sens des aiguilles d'une montre. Repère du modèle : avant vers +z, gauche
// vers +x, haut vers +y, origine au sol entre les essieux.

import * as THREE from 'three'

// Lada Niva 2121 trois portes.
export const NIVA = { wheelbase: 2.2, track: 1.43, wheelRadius: 0.343, length: 3.74, width: 1.68 }

const G = 9.81
const ENGINE = 5.4          // m/s², en courte : de quoi gravir ~55 %
const REVERSE = 2.6
const BRAKE = 7.5
const MAX_GRADE = 0.58      // au-delà, les roues patinent : la Niva recule
const MAX_ROLL = 0.7        // ~35° de dévers : on n'y va pas
const WARN_ROLL = 0.4
const MAX_STEER = 0.6
const STEER_RATE = 2.4      // rad/s
const REVERSE_MAX = 15 / 3.6
const FOREST = [8, 9, 80, 90]

export function createNivaState(x, z, heading) {
  return { x, z, heading, speed: 0, steer: 0, wheelSpin: 0, braking: false, status: null, warning: null,
           pitch: 0, roll: 0, ground: 0, wheels: null }
}

// La vitesse permise par le sol sous la voiture : route, prairie, sous-bois.
function speedLimit(cell) {
  if (!cell) return 40 / 3.6
  if (cell.landcover === 1) return 60 / 3.6
  if (FOREST.includes(cell.landcover) && cell.above > 4) return 12 / 3.6
  return 40 / 3.6
}

// Ce qui arrête la voiture : un mur, une mare, le bord du relief.
function obstacle(cell) {
  if (!cell) return 'Bord du relief'
  if (cell.landcover === 2 && cell.above > 1.5) return 'Un bâtiment barre le passage'
  if (cell.landcover === 5 || cell.dug > 0.6) return 'Eau trop profonde'
  return null
}

// Les quatre roues au sol : hauteurs dans l'ordre avant gauche, avant droite,
// arrière gauche, arrière droite.
function wheelHeights(terrain, x, z, heading) {
  const fx = Math.sin(heading)
  const fz = -Math.cos(heading)
  const lx = -Math.cos(heading)
  const lz = -Math.sin(heading)
  const a = NIVA.wheelbase / 2
  const b = NIVA.track / 2
  return [[a, b], [a, -b], [-a, b], [-a, -b]].map(([f, l]) => terrain.height(x + fx * f + lx * l, z + fz * f + lz * l))
}

function attitude(wheels) {
  const [fl, fr, rl, rr] = wheels
  return {
    pitch: ((fl + fr) - (rl + rr)) / 2 / NIVA.wheelbase,
    roll: ((fl + rl) - (fr + rr)) / 2 / NIVA.track,
    ground: (fl + fr + rl + rr) / 4,
  }
}

// Un pas de conduite. `input` : { throttle (-1 recule / freine … 1 avance),
// steer (-1 gauche … 1 droite), brake (frein à main) }. `terrain` :
// { width, depth, height(x, z), cell(x, z) → { landcover, above, dug } | null }.
export function stepNiva(state, input, terrain, dt) {
  dt = Math.min(dt, 0.05)
  state.status = null
  state.warning = null

  // La direction revient seule au centre ; moins de braquage à vive allure.
  const maxSteer = MAX_STEER / (1 + Math.abs(state.speed) / 9)
  const targetSteer = input.steer * maxSteer
  const delta = targetSteer - state.steer
  state.steer += Math.sign(delta) * Math.min(Math.abs(delta), STEER_RATE * dt)

  const wheels = state.wheels || wheelHeights(terrain, state.x, state.z, state.heading)
  const { pitch, roll } = attitude(wheels)
  const sinPitch = pitch / Math.hypot(1, pitch)
  const cell = terrain.cell(state.x, state.z)

  let accel = 0
  const moving = Math.abs(state.speed) > 0.05
  state.braking = false
  if (input.brake) {
    accel -= Math.sign(state.speed) * BRAKE
    state.braking = true
  } else if (input.throttle > 0) {
    if (state.speed < -0.2) { accel += BRAKE; state.braking = true } else accel += ENGINE * input.throttle
  } else if (input.throttle < 0) {
    if (state.speed > 0.2) { accel -= BRAKE; state.braking = true } else accel -= REVERSE
  }

  // Trop raide dans le sens de la marche : les roues patinent, le moteur ne
  // tire plus et la pente reprend la main.
  const climbing = (input.throttle > 0 && pitch > MAX_GRADE) || (input.throttle < 0 && pitch < -MAX_GRADE)
  if (climbing) {
    accel = 0
    state.status = 'Trop raide : les roues patinent'
  }

  // À l'arrêt sans gaz, la Niva tient sur son frein à main tant que la pente
  // le permet ; sinon la pente l'entraîne.
  const parked = input.throttle === 0 && Math.abs(state.speed) < 0.4 && Math.abs(pitch) < MAX_GRADE
  if (parked) {
    state.speed = 0
  } else {
    accel -= G * sinPitch
    if (moving) accel -= Math.sign(state.speed) * (0.5 + 0.035 * state.speed * state.speed)
    const before = state.speed
    state.speed += accel * dt
    // Le freinage arrête, il ne repart pas en arrière.
    if (state.braking && Math.sign(before) !== Math.sign(state.speed)) state.speed = 0
  }

  const limit = speedLimit(cell)
  if (state.speed > limit) state.speed -= (state.speed - limit) * Math.min(1, dt * 2)
  if (state.speed < -REVERSE_MAX) state.speed = -REVERSE_MAX

  const heading = state.heading + (state.speed / NIVA.wheelbase) * Math.tan(state.steer) * dt
  const step = state.speed * dt
  const x = state.x + Math.sin(heading) * step
  const z = state.z - Math.cos(heading) * step

  // Le pare-chocs dans le sens de la marche ne doit rien toucher.
  const reach = Math.sign(step) * NIVA.length / 2
  const bumper = [x + Math.sin(heading) * reach, z - Math.cos(heading) * reach]
  const outside = bumper[0] < 2 || bumper[1] < 2 || bumper[0] > terrain.width - 2 || bumper[1] > terrain.depth - 2
  const blocked = outside ? 'Bord du relief' : obstacle(terrain.cell(bumper[0], bumper[1]))
  const nextWheels = blocked ? null : wheelHeights(terrain, x, z, heading)
  const nextRoll = nextWheels ? attitude(nextWheels).roll : 0
  const tipping = nextWheels && Math.abs(nextRoll) > MAX_ROLL && Math.abs(nextRoll) > Math.abs(roll)

  if (step !== 0 && (blocked || tipping)) {
    state.speed = -state.speed * 0.15
    state.status = blocked || 'Dévers trop fort : demi-tour'
  } else {
    state.x = x
    state.z = z
    state.heading = heading
    if (nextWheels) state.wheels = nextWheels
    state.wheelSpin += step / NIVA.wheelRadius
  }

  const now = attitude(state.wheels || wheels)
  state.pitch = now.pitch
  state.roll = now.roll
  state.ground = now.ground
  if (!state.status && Math.abs(now.roll) > WARN_ROLL) state.warning = 'Attention au dévers'
  if (!state.status && !state.warning && speedLimit(terrain.cell(state.x, state.z)) < 5 && Math.abs(state.speed) > 1) state.warning = 'Sous-bois : au pas'
  return state
}

// ---- Le modèle ---------------------------------------------------------------

const PAINT = '#4d5d3a'

export function buildNivaModel() {
  const root = new THREE.Group()
  root.name = 'niva'
  const paint = new THREE.MeshStandardMaterial({ color: PAINT, roughness: 0.92, metalness: 0.05 })
  const black = new THREE.MeshStandardMaterial({ color: '#1b1c1a', roughness: 0.75, metalness: 0.15 })
  const tube = new THREE.MeshStandardMaterial({ color: '#151615', roughness: 0.45, metalness: 0.55 })
  const glass = new THREE.MeshStandardMaterial({ color: '#16222b', roughness: 0.12, metalness: 0.4 })
  const rubber = new THREE.MeshStandardMaterial({ color: '#141414', roughness: 0.95 })
  const rim = new THREE.MeshStandardMaterial({ color: '#3e4636', roughness: 0.6, metalness: 0.3 })
  const lens = new THREE.MeshStandardMaterial({ color: '#d9e2e6', roughness: 0.2, emissive: '#fff4d6', emissiveIntensity: 0 })
  const led = new THREE.MeshStandardMaterial({ color: '#c9d3da', roughness: 0.3, emissive: '#f2f7ff', emissiveIntensity: 0 })
  const tail = new THREE.MeshStandardMaterial({ color: '#7a1414', roughness: 0.4, emissive: '#ff2a1a', emissiveIntensity: 0 })
  const amber = new THREE.MeshStandardMaterial({ color: '#d9822b', roughness: 0.4 })

  const add = (geometry, material, x, y, z, parent = root) => {
    const mesh = new THREE.Mesh(geometry, material)
    mesh.position.set(x, y, z)
    parent.add(mesh)
    return mesh
  }
  const box = (w, h, l, material, x, y, z, parent) => add(new THREE.BoxGeometry(w, h, l), material, x, y, z, parent)

  // La caisse : un bloc bas, l'habitacle en trapèze par-dessus.
  box(1.66, 0.6, 3.6, paint, 0, 0.72, -0.02)
  const profile = new THREE.Shape()
  profile.moveTo(-1.84, 0)
  profile.lineTo(0.8, 0)
  profile.lineTo(0.3, 0.6)
  profile.lineTo(-1.78, 0.6)
  profile.closePath()
  const cabin = new THREE.ExtrudeGeometry(profile, { depth: 1.56, bevelEnabled: false })
  cabin.rotateY(-Math.PI / 2)
  cabin.translate(0.78, 1.02, 0)
  add(cabin, paint, 0, 0, 0)

  // Les vitres.
  const windshield = box(1.42, 0.7, 0.02, glass, 0, 1.32, 0.56)
  windshield.rotation.x = -0.69
  windshield.position.add(new THREE.Vector3(0, 0.637, 0.77).multiplyScalar(0.012))
  for (const side of [1, -1]) {
    box(0.02, 0.44, 0.66, glass, side * 0.785, 1.31, -0.02)
    box(0.02, 0.44, 1.22, glass, side * 0.785, 1.31, -1.1)
    // Rétroviseurs.
    box(0.05, 0.11, 0.15, black, side * 0.87, 1.14, 0.6)
  }
  box(1.3, 0.44, 0.02, glass, 0, 1.31, -1.83)

  // Calandre, phares ronds, clignotants, pare-chocs.
  box(0.92, 0.17, 0.02, black, 0, 0.87, 1.79)
  const headlights = []
  for (const side of [1, -1]) {
    const light = add(new THREE.CylinderGeometry(0.09, 0.09, 0.05, 24).rotateX(Math.PI / 2), lens, side * 0.62, 0.87, 1.79)
    headlights.push(light)
    add(new THREE.TorusGeometry(0.095, 0.012, 8, 24), tube, side * 0.62, 0.87, 1.815)
    box(0.13, 0.05, 0.02, amber, side * 0.62, 0.68, 1.79)
    box(0.2, 0.15, 0.03, tail, side * 0.69, 0.8, -1.83)
  }
  box(1.72, 0.16, 0.14, black, 0, 0.5, 1.87)
  box(1.72, 0.16, 0.14, black, 0, 0.5, -1.89)

  // Le pare-buffle : deux montants, deux traverses, une barre LED dessus.
  for (const side of [1, -1]) add(new THREE.CylinderGeometry(0.032, 0.032, 0.72, 10), tube, side * 0.42, 0.78, 1.98)
  add(new THREE.CylinderGeometry(0.032, 0.032, 0.9, 10).rotateZ(Math.PI / 2), tube, 0, 1.13, 1.98)
  add(new THREE.CylinderGeometry(0.032, 0.032, 1.36, 10).rotateZ(Math.PI / 2), tube, 0, 0.66, 2.0)
  box(0.72, 0.075, 0.08, black, 0, 1.19, 1.98)
  const bullLed = box(0.66, 0.045, 0.01, led, 0, 1.19, 2.025)

  // La rampe de toit sur deux barres.
  box(1.5, 0.04, 0.05, black, 0, 1.645, 0.05)
  box(1.5, 0.04, 0.05, black, 0, 1.645, -1.25)
  box(1.22, 0.1, 0.13, black, 0, 1.71, 0.1)
  const roofLed = box(1.14, 0.06, 0.01, led, 0, 1.71, 0.17)

  // Les plaques.
  const plate = plateTexture('BK-131-GA')
  const plateMaterial = new THREE.MeshStandardMaterial({ map: plate, roughness: 0.5 })
  add(new THREE.PlaneGeometry(0.52, 0.11), plateMaterial, 0, 0.5, 1.942)
  const rearPlate = add(new THREE.PlaneGeometry(0.52, 0.11), plateMaterial, 0, 0.5, -1.962)
  rearPlate.rotation.y = Math.PI

  // Les roues : un pivot de braquage à l'avant, une rotation de roulement.
  const wheels = []
  const steering = []
  // Les passages de roue : un disque sombre de part et d'autre, par essieu.
  for (const z of [1.1, -1.1]) {
    add(new THREE.CylinderGeometry(0.4, 0.4, 1.672, 24).rotateZ(Math.PI / 2), rubber, 0, NIVA.wheelRadius, z)
  }
  for (const [x, z] of [[0.765, 1.1], [-0.765, 1.1], [0.765, -1.1], [-0.765, -1.1]]) {
    const pivot = new THREE.Group()
    pivot.position.set(x, NIVA.wheelRadius, z)
    root.add(pivot)
    const spin = new THREE.Group()
    pivot.add(spin)
    add(new THREE.CylinderGeometry(NIVA.wheelRadius, NIVA.wheelRadius, 0.2, 28).rotateZ(Math.PI / 2), rubber, 0, 0, 0, spin)
    add(new THREE.CylinderGeometry(0.2, 0.2, 0.205, 18).rotateZ(Math.PI / 2), rim, 0, 0, 0, spin)
    // Un rayon clair : on voit la roue tourner.
    box(0.21, 0.3, 0.05, tube, 0, 0, 0, spin)
    wheels.push(spin)
    if (z > 0) steering.push(pivot)
  }

  // L'ombre portée : une tache douce sous la caisse.
  const shadow = add(new THREE.PlaneGeometry(2.6, 4.6).rotateX(-Math.PI / 2), new THREE.MeshBasicMaterial({
    map: shadowTexture(), transparent: true, depthWrite: false, polygonOffset: true, polygonOffsetFactor: -2,
  }), 0, 0.04, 0)
  shadow.renderOrder = 1

  // La lumière : deux phares, la barre du pare-buffle, la rampe de toit.
  const spot = (color, distance, angle, x, y, z, aimY, aimZ) => {
    const light = new THREE.SpotLight(color, 0, distance, angle, 0.55, 1.3)
    light.position.set(x, y, z)
    light.target.position.set(x, aimY, aimZ)
    root.add(light, light.target)
    return light
  }
  const beams = {
    low: [spot('#fff1d0', 90, 0.42, 0.62, 0.87, 1.85, 0.1, 30), spot('#fff1d0', 90, 0.42, -0.62, 0.87, 1.85, 0.1, 30)],
    bull: [spot('#eef4ff', 45, 0.95, 0, 1.19, 2.05, 0, 14)],
    roof: [spot('#f2f6ff', 150, 0.62, 0, 1.71, 0.2, 0.2, 45)],
  }
  const cones = {
    low: headlights.map((h) => add(lightCone(18, 3.4), coneMaterial('#fff1c9'), h.position.x, 0.87, 1.84)),
    roof: [add(lightCone(26, 9), coneMaterial('#e9f1ff'), 0, 1.71, 0.2)],
  }
  for (const cone of [...cones.low, ...cones.roof]) cone.visible = false

  root.userData = { wheels, steering, lens, led, bullLed, roofLed, tail, beams, cones }
  return root
}

// Allume ou éteint : `lights` = { low, bar } (phares, rampe et barre LED) ;
// `braking` rallume les feux arrière.
export function setNivaLights(model, { low, bar, night, braking }) {
  const { lens, led, tail, beams, cones } = model.userData
  lens.emissiveIntensity = low ? 2.4 : 0
  led.emissiveIntensity = bar ? 3 : 0
  tail.emissiveIntensity = braking ? 2.2 : (low ? 0.8 : 0)
  for (const light of beams.low) light.intensity = low ? (night ? 150 : 20) : 0
  for (const light of beams.bull) light.intensity = bar ? (night ? 60 : 12) : 0
  for (const light of beams.roof) light.intensity = bar ? (night ? 160 : 40) : 0
  for (const cone of cones.low) cone.visible = Boolean(low && night)
  for (const cone of cones.roof) cone.visible = Boolean(bar && night)
}

// Un faisceau visible dans la nuit : un cône ouvert, opaque à la source et
// transparent au bout, additionné à la scène.
function lightCone(length, radius) {
  const geometry = new THREE.ConeGeometry(radius, length, 28, 6, true)
  geometry.translate(0, -length / 2, 0)
  geometry.rotateX(-Math.PI / 2)
  geometry.rotateX(0.06)
  const position = geometry.attributes.position
  const colors = new Float32Array(position.count * 4)
  for (let i = 0; i < position.count; i++) {
    const along = Math.min(1, Math.max(0, position.getZ(i) / length))
    colors.set([1, 1, 1, (1 - along) ** 1.6], i * 4)
  }
  geometry.setAttribute('color', new THREE.BufferAttribute(colors, 4))
  return geometry
}

function coneMaterial(color) {
  return new THREE.MeshBasicMaterial({
    color, vertexColors: true, transparent: true, opacity: 0.1, blending: THREE.AdditiveBlending,
    depthWrite: false, side: THREE.DoubleSide, fog: false,
  })
}

// Une plaque d'immatriculation : fond blanc, bandes bleues, caractères noirs.
function plateTexture(text) {
  const canvas = document.createElement('canvas')
  canvas.width = 520
  canvas.height = 110
  const ctx = canvas.getContext('2d')
  ctx.fillStyle = '#ffffff'
  ctx.fillRect(0, 0, 520, 110)
  ctx.fillStyle = '#1d4ea8'
  ctx.fillRect(0, 0, 46, 110)
  ctx.fillRect(474, 0, 46, 110)
  ctx.fillStyle = '#ffffff'
  ctx.font = 'bold 30px sans-serif'
  ctx.textAlign = 'center'
  ctx.fillText('F', 23, 92)
  ctx.fillStyle = '#111111'
  ctx.font = 'bold 76px sans-serif'
  ctx.textBaseline = 'middle'
  ctx.fillText(text, 260, 58)
  ctx.strokeStyle = '#111111'
  ctx.lineWidth = 4
  ctx.strokeRect(2, 2, 516, 106)
  const texture = new THREE.CanvasTexture(canvas)
  texture.colorSpace = THREE.SRGBColorSpace
  texture.anisotropy = 4
  return texture
}

function shadowTexture() {
  const canvas = document.createElement('canvas')
  canvas.width = 64
  canvas.height = 128
  const ctx = canvas.getContext('2d')
  const gradient = ctx.createRadialGradient(32, 64, 3, 32, 64, 31)
  gradient.addColorStop(0, 'rgba(0,0,0,0.55)')
  gradient.addColorStop(0.6, 'rgba(0,0,0,0.3)')
  gradient.addColorStop(1, 'rgba(0,0,0,0)')
  ctx.setTransform(1, 0, 0, 2, 0, -64)
  ctx.fillStyle = gradient
  ctx.fillRect(0, 0, 64, 128)
  return new THREE.CanvasTexture(canvas)
}
