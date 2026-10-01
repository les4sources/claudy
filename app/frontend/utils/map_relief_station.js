// La « station » de chaque mètre carré, pour placer les espèces : pente,
// exposition, humidité et risque de gel, tirés du seul relief (MNT LiDAR) et des
// axes d'écoulement de `map_relief_hydro.js`.
//
// Humidité et gel sont des INDICES, pas des mesures : ils disent où le relief
// rassemble l'eau ou l'air froid, pas ce que le sol contient vraiment. L'interface
// les présente comme tels.
//
// Comme les autres modules du relief, rien n'est importé : on peut l'exercer seul.

// Pente (radians) et exposition (radians depuis le nord, sens horaire : le côté
// vers lequel la pente DESCEND, celui qui « regarde » le ciel) par la méthode de
// Horn, sur les huit voisines. Bords : la maille voisine la plus proche.
export function slopeAspect(heights, cols, rows, cellSize = 1) {
  const slope = new Float32Array(cols * rows)
  const aspect = new Float32Array(cols * rows)
  const at = (c, r) => heights[Math.min(rows - 1, Math.max(0, r)) * cols + Math.min(cols - 1, Math.max(0, c))]
  for (let r = 0; r < rows; r++) {
    for (let c = 0; c < cols; c++) {
      const a = at(c - 1, r - 1); const b = at(c, r - 1); const d = at(c + 1, r - 1)
      const e = at(c - 1, r); const f = at(c + 1, r)
      const g = at(c - 1, r + 1); const h = at(c, r + 1); const k = at(c + 1, r + 1)
      // Vers l'est et vers le NORD (les lignes descendent vers le sud).
      const dzdx = ((d + 2 * f + k) - (a + 2 * e + g)) / (8 * cellSize)
      const dzdy = ((a + 2 * b + d) - (g + 2 * h + k)) / (8 * cellSize)
      const i = r * cols + c
      slope[i] = Math.atan(Math.hypot(dzdx, dzdy))
      // La pente descend à l'opposé du gradient.
      let direction = Math.atan2(-dzdx, -dzdy)
      if (direction < 0) direction += 2 * Math.PI
      aspect[i] = direction
    }
  }
  return { slope, aspect }
}

// Flou en boîte séparable (rayon en mailles) : les indices à 1 m sont trop
// hachés pour être lus, une moyenne sur quelques mètres les rend lisibles.
export function boxBlur(values, cols, rows, radius) {
  if (radius < 1) return Float32Array.from(values)
  const tmp = new Float32Array(values.length)
  const out = new Float32Array(values.length)
  for (let r = 0; r < rows; r++) {
    let sum = 0
    let n = 0
    const base = r * cols
    for (let c = 0; c <= Math.min(radius, cols - 1); c++) { sum += values[base + c]; n++ }
    for (let c = 0; c < cols; c++) {
      tmp[base + c] = sum / n
      const add = c + radius + 1
      const drop = c - radius
      if (add < cols) { sum += values[base + add]; n++ }
      if (drop >= 0) { sum -= values[base + drop]; n-- }
    }
  }
  for (let c = 0; c < cols; c++) {
    let sum = 0
    let n = 0
    for (let r = 0; r <= Math.min(radius, rows - 1); r++) { sum += tmp[r * cols + c]; n++ }
    for (let r = 0; r < rows; r++) {
      out[r * cols + c] = sum / n
      const add = r + radius + 1
      const drop = r - radius
      if (add < rows) { sum += tmp[add * cols + c]; n++ }
      if (drop >= 0) { sum -= tmp[drop * cols + c]; n-- }
    }
  }
  return out
}

// La surface drainée en écoulement RÉPARTI (Quinn et al., 1991) : chaque maille
// partage son eau entre toutes ses voisines plus basses, au prorata de la pente.
// L'écoulement vers une seule voisine (`analyzeDrainage`) dessine bien les axes,
// mais à 1 m il vide les pentes : l'indice d'humidité a besoin de cette eau
// diffuse. Sur le relief aux cuvettes remplies, parcouru de l'amont vers l'aval.
export function spreadAccumulation(drainage, cols, rows, cellSize = 1) {
  const { filled, order } = drainage
  const n = cols * rows
  const area = cellSize * cellSize
  const accumulation = new Float32Array(n).fill(area)
  const weights = new Float64Array(8)
  const targets = new Int32Array(8)
  for (let k = n - 1; k >= 0; k--) {
    const i = order[k]
    const c = i % cols
    const r = (i - c) / cols
    let total = 0
    let count = 0
    for (let dr = -1; dr <= 1; dr++) {
      for (let dc = -1; dc <= 1; dc++) {
        if (!dr && !dc) continue
        const cc = c + dc
        const rr = r + dr
        if (cc < 0 || rr < 0 || cc >= cols || rr >= rows) continue
        const j = rr * cols + cc
        const drop = filled[i] - filled[j]
        if (drop <= 0) continue
        const diagonal = dr && dc
        const w = Math.pow(drop / (diagonal ? Math.SQRT2 : 1), 1.1) * (diagonal ? 0.354 : 0.5)
        weights[count] = w
        targets[count] = j
        total += w
        count++
      }
    }
    if (!count) continue
    for (let m = 0; m < count; m++) accumulation[targets[m]] += accumulation[i] * (weights[m] / total)
  }
  return accumulation
}

// L'indice topographique d'humidité (Beven & Kirkby) : ln(a / tan β), où `a`
// est la surface drainée par mètre de courbe et β la pente. Haut là où beaucoup
// d'eau arrive sur une pente faible (fonds de vallon, replats au pied des
// pentes), bas sur les crêtes et les pentes raides.
export function wetnessIndex(accumulation, slope, cellSize = 1) {
  const twi = new Float32Array(accumulation.length)
  for (let i = 0; i < twi.length; i++) {
    const tan = Math.max(Math.tan(slope[i]), 0.001)
    twi[i] = Math.log(accumulation[i] / cellSize / tan)
  }
  return twi
}

// Le risque de gel par accumulation d'air froid, de 0 à 1. La nuit, l'air froid
// coule comme l'eau et s'arrête dans les fonds : on mesure la hauteur de chaque
// maille au-dessus du drain où son eau finirait (« HAND », Height Above Nearest
// Drainage) — à 0 m on est dans le fond, à 10 m et plus on est sur la pente,
// dans la « ceinture chaude ». Les cuvettes fermées gardent leur lac d'air froid.
//
// `drainage` : la sortie de `analyzeDrainage` (receveurs, ordre, cuvettes,
// surfaces drainées). Un drain = une maille qui draine au moins `channelArea` m².
export function frostRisk(heights, drainage, { channelArea = 50000, warmBelt = 10 } = {}) {
  const { receiver, order, accumulation, depression } = drainage
  const n = heights.length
  const drainLevel = new Float32Array(n)
  // L'ordre du flood va de l'aval vers l'amont : le receveur est toujours
  // traité avant la maille qui s'y écoule.
  for (let k = 0; k < n; k++) {
    const i = order[k]
    const to = receiver[i]
    drainLevel[i] = accumulation[i] >= channelArea || to < 0 ? heights[i] : drainLevel[to]
  }
  const risk = new Float32Array(n)
  for (let i = 0; i < n; i++) {
    const hand = Math.max(0, heights[i] - drainLevel[i])
    let value = 1 - hand / warmBelt
    if (depression[i] > 0.2) value = Math.max(value, 0.8)
    risk[i] = value < 0 ? 0 : value > 1 ? 1 : value
  }
  return risk
}

const COMPASS = ['nord', 'nord-est', 'est', 'sud-est', 'sud', 'sud-ouest', 'ouest', 'nord-ouest']

export function compassName(aspect) {
  return COMPASS[Math.round(aspect / (Math.PI / 4)) % 8]
}

// « vers le nord », « vers l'est »…
export function towards(aspect) {
  const name = compassName(aspect)
  return /^[eo]/.test(name) ? `vers l'${name}` : `vers le ${name}`
}

// Seuils calés sur le domaine (MNT à 1 m, écoulement réparti, flou de 2 m) :
// le sommet sort à 2,7, la prairie en pente de 16 % à 5,8, le ruisseau à 14.
// Les seuils publiés pour des MNT à 10-30 m donneraient 95 % de « sec » ici.
export function wetnessClass(twi) {
  if (twi < 4.5) return 'sec'
  if (twi < 6.5) return 'frais'
  if (twi < 9) return 'humide'
  return 'très humide'
}

export function frostClass(risk) {
  if (risk >= 0.66) return 'fort'
  if (risk >= 0.33) return 'modéré'
  return 'faible'
}
