// L'hydrologie de la vue 3D du relief (`/map/relief`).
//
// Deux calculs sur la grille d'altitudes du MNT, sans aucune dépendance (ni
// three.js ni DOM) pour qu'on puisse les exercer seuls :
//
// - `analyzeDrainage` : les axes d'écoulement. Un « priority-flood » (Barnes,
//   2014) remplit les cuvettes depuis les bords, et chaque maille s'écoule vers
//   celle qui l'a atteinte. On en tire la surface drainée par chaque maille (où
//   l'eau se rassemble) et la profondeur des cuvettes (où elle stagne).
// - `RainSimulation` : la pluie qui ruisselle, par le modèle des « tuyaux
//   virtuels » (O'Brien & Hodgins 1995, Mei et al. 2007) — une lame d'eau par
//   maille, des débits vers les quatre voisines poussés par la différence de
//   niveau d'eau, ralentis par un frottement. L'eau quitte la grille par ses
//   bords : le bilan (pluie − infiltration − sortie = eau présente) est tenu à
//   chaque pas.

const GRAVITY = 9.81

// Décode `grid.bin` (Uint16 en cm au-dessus de `z_min`, 65535 = sans donnée)
// en altitudes en mètres. Un trou prend la moyenne de ses voisines connues,
// balayée jusqu'à ce qu'il n'en reste plus — le SPW n'en laisse que sur l'eau
// libre ou les bords de dalles.
export function decodeGrid(buffer, meta) {
  const raw = new Uint16Array(buffer)
  const { cols, rows } = meta
  const zMin = Number(meta.z_min)
  const unit = Number(meta.z_unit || 0.01)
  const nodata = meta.nodata ?? 65535
  if (raw.length !== cols * rows) throw new Error(`Grille de ${raw.length} valeurs pour ${cols} × ${rows}`)

  const heights = new Float32Array(raw.length)
  const missing = []
  for (let i = 0; i < raw.length; i++) {
    if (raw[i] === nodata) {
      heights[i] = NaN
      missing.push(i)
    } else {
      heights[i] = zMin + raw[i] * unit
    }
  }
  let pending = missing
  while (pending.length) {
    const still = []
    for (const i of pending) {
      const c = i % cols
      const r = (i - c) / cols
      let sum = 0
      let n = 0
      for (const [dc, dr] of [[1, 0], [-1, 0], [0, 1], [0, -1]]) {
        const cc = c + dc
        const rr = r + dr
        if (cc < 0 || rr < 0 || cc >= cols || rr >= rows) continue
        const v = heights[rr * cols + cc]
        if (!Number.isNaN(v)) { sum += v; n++ }
      }
      if (n) heights[i] = sum / n
      else still.push(i)
    }
    if (still.length === pending.length) {
      still.forEach((i) => { heights[i] = zMin })
      break
    }
    pending = still
  }
  return heights
}

// Moyenne par blocs `factor × factor` : la grille de simulation (2 m) à partir
// de celle du relief (1 m).
export function downsample(heights, cols, rows, factor) {
  if (factor <= 1) return { heights: Float32Array.from(heights), cols, rows }
  const outCols = Math.floor(cols / factor)
  const outRows = Math.floor(rows / factor)
  const out = new Float32Array(outCols * outRows)
  const area = factor * factor
  for (let r = 0; r < outRows; r++) {
    for (let c = 0; c < outCols; c++) {
      let sum = 0
      for (let dr = 0; dr < factor; dr++) {
        const base = (r * factor + dr) * cols + c * factor
        for (let dc = 0; dc < factor; dc++) sum += heights[base + dc]
      }
      out[r * outCols + c] = sum / area
    }
  }
  return { heights: out, cols: outCols, rows: outRows }
}

// Un tas binaire minimal sur des indices de mailles, ordonné par une clé
// Float64 : le priority-flood en fait sortir ~750 000, un tableau trié à chaque
// insertion serait quadratique.
class MinHeap {
  constructor(capacity) {
    this.keys = new Float64Array(capacity)
    this.items = new Int32Array(capacity)
    this.size = 0
  }

  push(item, key) {
    let i = this.size++
    while (i > 0) {
      const parent = (i - 1) >> 1
      if (this.keys[parent] <= key) break
      this.keys[i] = this.keys[parent]
      this.items[i] = this.items[parent]
      i = parent
    }
    this.keys[i] = key
    this.items[i] = item
  }

  pop() {
    const top = this.items[0]
    const last = --this.size
    if (last > 0) {
      const key = this.keys[last]
      const item = this.items[last]
      let i = 0
      for (;;) {
        let child = 2 * i + 1
        if (child >= last) break
        if (child + 1 < last && this.keys[child + 1] < this.keys[child]) child++
        if (this.keys[child] >= key) break
        this.keys[i] = this.keys[child]
        this.items[i] = this.items[child]
        i = child
      }
      this.keys[i] = key
      this.items[i] = item
    }
    return top
  }
}

const NEIGHBORS = [[1, 0], [-1, 0], [0, 1], [0, -1], [1, 1], [1, -1], [-1, 1], [-1, -1]]

// Les axes d'écoulement et les cuvettes.
//
// Le flood part des bords (l'eau quitte la grille par là) et avance toujours par
// la maille la plus basse déjà atteinte ; chaque maille découverte s'écoule
// vers celle qui l'a découverte, et son niveau rempli ne descend jamais sous
// celui de son aval (+ un epsilon qui garde une pente sur les replats). L'ordre
// de sortie du tas va de l'aval vers l'amont : le parcourir à l'envers cumule
// les surfaces drainées en un seul passage.
//
// Renvoie `accumulation` (m² drainés par maille), `depression` (profondeur de
// cuvette en m), `receiver` (maille aval, -1 sur les bords) et `order` (de
// l'aval vers l'amont, chaque receveur avant ses donneurs) et `filled` (le
// relief aux cuvettes remplies).
export function analyzeDrainage(heights, cols, rows, cellSize = 1) {
  const n = cols * rows
  const filled = new Float64Array(n)
  const receiver = new Int32Array(n).fill(-1)
  const seen = new Uint8Array(n)
  const order = new Int32Array(n)
  const heap = new MinHeap(n)
  const epsilon = 1e-5

  for (let c = 0; c < cols; c++) {
    for (const r of [0, rows - 1]) {
      const i = r * cols + c
      if (!seen[i]) { seen[i] = 1; filled[i] = heights[i]; heap.push(i, heights[i]) }
    }
  }
  for (let r = 1; r < rows - 1; r++) {
    for (const c of [0, cols - 1]) {
      const i = r * cols + c
      if (!seen[i]) { seen[i] = 1; filled[i] = heights[i]; heap.push(i, heights[i]) }
    }
  }

  let count = 0
  while (heap.size) {
    const i = heap.pop()
    order[count++] = i
    const c = i % cols
    const r = (i - c) / cols
    for (const [dc, dr] of NEIGHBORS) {
      const cc = c + dc
      const rr = r + dr
      if (cc < 0 || rr < 0 || cc >= cols || rr >= rows) continue
      const j = rr * cols + cc
      if (seen[j]) continue
      seen[j] = 1
      receiver[j] = i
      filled[j] = Math.max(heights[j], filled[i] + epsilon)
      heap.push(j, filled[j])
    }
  }

  const cellArea = cellSize * cellSize
  const accumulation = new Float32Array(n).fill(cellArea)
  for (let k = n - 1; k >= 0; k--) {
    const i = order[k]
    const to = receiver[i]
    if (to >= 0) accumulation[to] += accumulation[i]
  }

  const depression = new Float32Array(n)
  for (let i = 0; i < n; i++) {
    const depth = filled[i] - heights[i]
    depression[i] = depth > 0.01 ? depth : 0
  }

  return { accumulation, depression, receiver, order, filled }
}

// La pluie sur le relief, pas à pas.
//
// `heights` : le terrain (m), `cellSize` : le côté d'une maille (m). Les options
// se changent en cours de route (`setOptions`) : intensité et infiltration en
// mm/h, durée de l'averse en minutes (0 = sans fin).
export class RainSimulation {
  constructor(heights, cols, rows, cellSize, options = {}) {
    this.ground = Float32Array.from(heights)
    this.cols = cols
    this.rows = rows
    this.cellSize = cellSize
    const n = cols * rows
    this.depth = new Float32Array(n)
    // Débits sortants vers la droite, la gauche, le bas (sud) et le haut (nord),
    // en m³/s.
    this.fluxR = new Float32Array(n)
    this.fluxL = new Float32Array(n)
    this.fluxB = new Float32Array(n)
    this.fluxT = new Float32Array(n)
    // Vitesse moyenne de l'eau dans chaque maille (m/s), pour les traceurs.
    this.velX = new Float32Array(n)
    this.velY = new Float32Array(n)
    this.options = { intensity: 30, infiltration: 5, duration: 60, friction: 0.5 }
    this.setOptions(options)
    this.reset()
  }

  setOptions(options) {
    Object.assign(this.options, options)
  }

  reset() {
    this.depth.fill(0)
    this.fluxR.fill(0)
    this.fluxL.fill(0)
    this.fluxB.fill(0)
    this.fluxT.fill(0)
    this.velX.fill(0)
    this.velY.fill(0)
    this.time = 0
    this.rained = 0
    this.infiltrated = 0
    this.outflow = 0
  }

  get raining() {
    const minutes = this.options.duration
    return !(minutes > 0) || this.time < minutes * 60
  }

  // Le volume d'eau présent sur la grille (m³).
  stored() {
    let sum = 0
    for (let i = 0; i < this.depth.length; i++) sum += this.depth[i]
    return sum * this.cellSize * this.cellSize
  }

  // Un pas de `dt` secondes. Au-delà de ~1 s sur une maille de 2 m, le modèle
  // oscille : l'appelant enchaîne des petits pas plutôt qu'un grand.
  step(dt) {
    const { cols, rows, cellSize, ground, depth, fluxR, fluxL, fluxB, fluxT } = this
    const n = cols * rows
    const area = cellSize * cellSize
    const rain = this.raining ? (this.options.intensity / 1000 / 3600) * dt : 0
    const infiltration = (this.options.infiltration / 1000 / 3600) * dt
    // Le frottement amortit les débits d'une fraction par seconde : sans lui,
    // l'eau accélérerait sans fin dans la pente.
    const keep = Math.max(0, 1 - this.options.friction * dt)
    const pipe = dt * GRAVITY * cellSize

    // 1. La pluie tombe, le sol en boit une part.
    let rainedStep = 0
    let infiltratedStep = 0
    for (let i = 0; i < n; i++) {
      let d = depth[i] + rain
      rainedStep += rain
      const soaked = d < infiltration ? d : infiltration
      d -= soaked
      infiltratedStep += soaked
      depth[i] = d
    }

    // 2. Les débits vers les voisines suivent la différence de niveau d'eau. Au
    //    bord, la voisine absente est le sol sans eau : l'eau s'en va.
    let outflowStep = 0
    for (let r = 0; r < rows; r++) {
      for (let c = 0; c < cols; c++) {
        const i = r * cols + c
        const d = depth[i]
        const level = ground[i] + d
        const right = c + 1 < cols ? ground[i + 1] + depth[i + 1] : ground[i]
        const left = c > 0 ? ground[i - 1] + depth[i - 1] : ground[i]
        const bottom = r + 1 < rows ? ground[i + cols] + depth[i + cols] : ground[i]
        const top = r > 0 ? ground[i - cols] + depth[i - cols] : ground[i]
        let fR = fluxR[i] * keep + pipe * (level - right)
        let fL = fluxL[i] * keep + pipe * (level - left)
        let fB = fluxB[i] * keep + pipe * (level - bottom)
        let fT = fluxT[i] * keep + pipe * (level - top)
        if (fR < 0) fR = 0
        if (fL < 0) fL = 0
        if (fB < 0) fB = 0
        if (fT < 0) fT = 0
        const total = (fR + fL + fB + fT) * dt
        const available = d * area
        // Jamais plus d'eau sortie qu'il n'y en a : on réduit tous les débits
        // de la maille dans la même proportion.
        if (total > available) {
          const k = total > 0 ? available / total : 0
          fR *= k; fL *= k; fB *= k; fT *= k
        }
        fluxR[i] = fR
        fluxL[i] = fL
        fluxB[i] = fB
        fluxT[i] = fT
        if (c + 1 === cols) outflowStep += fR * dt
        if (c === 0) outflowStep += fL * dt
        if (r + 1 === rows) outflowStep += fB * dt
        if (r === 0) outflowStep += fT * dt
      }
    }

    // 3. Chaque maille reçoit ce que ses voisines lui envoient et perd ce
    //    qu'elle envoie.
    const { velX, velY } = this
    for (let r = 0; r < rows; r++) {
      for (let c = 0; c < cols; c++) {
        const i = r * cols + c
        const inR = c > 0 ? fluxR[i - 1] : 0
        const inL = c + 1 < cols ? fluxL[i + 1] : 0
        const inB = r > 0 ? fluxB[i - cols] : 0
        const inT = r + 1 < rows ? fluxT[i + cols] : 0
        const out = fluxR[i] + fluxL[i] + fluxB[i] + fluxT[i]
        const before = depth[i]
        let after = before + ((inR + inL + inB + inT - out) * dt) / area
        if (after < 0) after = 0
        depth[i] = after
        const mean = (before + after) / 2
        if (mean > 1e-4) {
          velX[i] = (inR - fluxL[i] + fluxR[i] - inL) / 2 / (cellSize * mean)
          velY[i] = (inB - fluxT[i] + fluxB[i] - inT) / 2 / (cellSize * mean)
        } else {
          velX[i] = 0
          velY[i] = 0
        }
      }
    }

    this.time += dt
    this.rained += rainedStep * area
    this.infiltrated += infiltratedStep * area
    this.outflow += outflowStep
  }
}
