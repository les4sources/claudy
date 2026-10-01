// Les aménagements à l'essai sur le relief (`/map/relief`) : baissières,
// keylines et mares, tracés sur le MNT puis « creusés » dans une copie du relief
// pour que la pluie simulée et les axes d'écoulement en tiennent compte.
//
// Coordonnées : en mètres sur la grille du MNT, x vers l'est depuis la première
// colonne, y vers le SUD depuis la première ligne (une maille = `cellSize` m).
// Le relief stocké n'est jamais modifié : `applyDesigns` en rend une copie.
//
// Comme les autres modules du relief, rien n'est importé : on peut l'exercer seul.

// Altitude interpolée (bilinéaire) en un point de la grille.
export function heightAt(heights, cols, rows, cellSize, x, y) {
  const fx = Math.min(cols - 1.001, Math.max(0, x / cellSize))
  const fy = Math.min(rows - 1.001, Math.max(0, y / cellSize))
  const c = Math.floor(fx)
  const r = Math.floor(fy)
  const tx = fx - c
  const ty = fy - r
  const i = r * cols + c
  const top = heights[i] * (1 - tx) + heights[i + 1] * tx
  const bottom = heights[i + cols] * (1 - tx) + heights[i + cols + 1] * tx
  return top * (1 - ty) + bottom * ty
}

function gradientAt(heights, cols, rows, cellSize, x, y) {
  const d = cellSize
  return [
    (heightAt(heights, cols, rows, cellSize, x + d, y) - heightAt(heights, cols, rows, cellSize, x - d, y)) / (2 * d),
    (heightAt(heights, cols, rows, cellSize, x, y + d) - heightAt(heights, cols, rows, cellSize, x, y - d)) / (2 * d),
  ]
}

// Une ligne qui suit la courbe de niveau depuis `start`, dans la direction de
// `toward`, en descendant de `grade` % (0 = baissière à niveau, 0,5 à 2 % = une
// keyline ou une rigole qui mène l'eau quelque part). Elle s'arrête quand elle a
// dépassé le point visé, au bord de la grille, sur un replat sans pente, ou à
// `maxLength` mètres. Rend des points tous les mètres, avec leur niveau visé.
export function traceContour(heights, cols, rows, cellSize, start, toward, { grade = 0, maxLength = 400 } = {}) {
  const step = 0.5
  const width = (cols - 1) * cellSize
  const height = (rows - 1) * cellSize
  const z0 = heightAt(heights, cols, rows, cellSize, start.x, start.y)
  const aim = [toward.x - start.x, toward.y - start.y]
  const reach = Math.hypot(aim[0], aim[1])
  const points = [{ x: start.x, y: start.y, z: z0 }]
  let x = start.x
  let y = start.y
  let previous = null
  let travelled = 0
  let best = Infinity
  let sinceBest = 0
  while (travelled < maxLength) {
    const [gx, gy] = gradientAt(heights, cols, rows, cellSize, x, y)
    const norm = Math.hypot(gx, gy)
    if (norm < 1e-4) break
    // La tangente à la courbe : perpendiculaire au gradient, du côté visé
    // (ou dans la continuité du pas précédent).
    let tx = -gy / norm
    let ty = gx / norm
    const reference = previous || aim
    if (tx * reference[0] + ty * reference[1] < 0) { tx = -tx; ty = -ty }
    let nx = x + tx * step
    let ny = y + ty * step
    const target = z0 - (grade / 100) * (travelled + step)
    // Ramener le point sur le niveau visé, le long du gradient.
    for (let k = 0; k < 4; k++) {
      const [hx, hy] = gradientAt(heights, cols, rows, cellSize, nx, ny)
      const g2 = hx * hx + hy * hy
      if (g2 < 1e-8) break
      const error = heightAt(heights, cols, rows, cellSize, nx, ny) - target
      const shift = Math.max(-1, Math.min(1, error / g2))
      nx -= hx * shift
      ny -= hy * shift
    }
    if (nx < 0 || ny < 0 || nx > width || ny > height) break
    previous = [nx - x, ny - y]
    travelled += Math.hypot(nx - x, ny - y)
    x = nx
    y = ny
    if (travelled - (points.length - 1) >= 1) points.push({ x, y, z: target })
    // Arrivé à hauteur du point visé : on s'arrête quand on s'en éloigne.
    const distance = Math.hypot(toward.x - x, toward.y - y)
    if (distance < best) { best = distance; sinceBest = 0 } else sinceBest += step
    if (travelled > 2 && (distance < 1 || (travelled >= reach * 0.5 && sinceBest > 1))) break
  }
  const last = points[points.length - 1]
  if (last.x !== x || last.y !== y) points.push({ x, y, z: z0 - (grade / 100) * travelled })
  return { points, length: travelled, level: z0 }
}

// Distance d'un point à un segment, et position (0..1) du pied sur le segment.
function segmentDistance(px, py, a, b) {
  const dx = b.x - a.x
  const dy = b.y - a.y
  const length2 = dx * dx + dy * dy
  let t = length2 ? ((px - a.x) * dx + (py - a.y) * dy) / length2 : 0
  t = Math.max(0, Math.min(1, t))
  const qx = a.x + t * dx
  const qy = a.y + t * dy
  return { distance: Math.hypot(px - qx, py - qy), t, side: dx * (py - a.y) - dy * (px - a.x) }
}

// Creuse une baissière (ou keyline) dans `out` : une tranchée de `width` m à
// `depth` m sous le niveau de la ligne, et une butte de `berm` m au-dessus de ce
// niveau, de la même largeur, côté aval. Rend les mailles touchées.
function digSwale(out, base, cols, rows, cellSize, design) {
  const { points } = design
  const width = design.width ?? 2
  const depth = design.depth ?? 0.5
  const berm = design.berm ?? 0.4
  const half = width / 2
  const reach = half + width
  const touched = []
  if (!points || points.length < 2) return touched
  // Le côté aval de chaque segment : celui où le terrain est plus bas.
  const downhill = []
  for (let k = 0; k < points.length - 1; k++) {
    const a = points[k]
    const b = points[k + 1]
    const length = Math.hypot(b.x - a.x, b.y - a.y) || 1
    const nx = -(b.y - a.y) / length
    const ny = (b.x - a.x) / length
    const mx = (a.x + b.x) / 2
    const my = (a.y + b.y) / 2
    const left = heightAt(base, cols, rows, cellSize, mx + nx * 2, my + ny * 2)
    const right = heightAt(base, cols, rows, cellSize, mx - nx * 2, my - ny * 2)
    // `side` > 0 du côté de la normale (nx, ny).
    downhill.push(left < right ? 1 : -1)
  }
  let minX = Infinity; let minY = Infinity; let maxX = -Infinity; let maxY = -Infinity
  for (const p of points) {
    minX = Math.min(minX, p.x); maxX = Math.max(maxX, p.x)
    minY = Math.min(minY, p.y); maxY = Math.max(maxY, p.y)
  }
  const c0 = Math.max(0, Math.floor((minX - reach) / cellSize))
  const c1 = Math.min(cols - 1, Math.ceil((maxX + reach) / cellSize))
  const r0 = Math.max(0, Math.floor((minY - reach) / cellSize))
  const r1 = Math.min(rows - 1, Math.ceil((maxY + reach) / cellSize))
  for (let r = r0; r <= r1; r++) {
    for (let c = c0; c <= c1; c++) {
      const px = c * cellSize
      const py = r * cellSize
      let nearest = null
      for (let k = 0; k < points.length - 1; k++) {
        const hit = segmentDistance(px, py, points[k], points[k + 1])
        if (!nearest || hit.distance < nearest.distance) nearest = { ...hit, k }
      }
      if (!nearest || nearest.distance > reach) continue
      const a = points[nearest.k]
      const b = points[nearest.k + 1]
      const level = a.z + (b.z - a.z) * nearest.t
      const i = r * cols + c
      // Toute maille de l'ouvrage fait partie de son empreinte, creusée ou non
      // (un terrain déjà plus bas, une butte contre une pente plus haute) : sans
      // elle, la capacité verrait un faux déversoir. Au moins 3/4 de maille de
      // demi-largeur garde la tranchée continue en diagonale.
      if (nearest.distance <= Math.max(half, cellSize * 0.75)) {
        out[i] = Math.min(out[i], level - depth)
        touched.push(i)
      } else if (berm > 0 && Math.sign(nearest.side) === downhill[nearest.k]) {
        out[i] = Math.max(out[i], level + berm)
        touched.push(i)
      }
    }
  }
  return touched
}

// Creuse une mare : une cuvette de `radius` m et `depth` m au centre (profil
// parabolique) sous le niveau du terrain au centre, ceinte d'une digue de
// `berm` m au-dessus de ce niveau, large de 2 m. Sur une pente, la digue retient
// l'eau côté aval ; côté amont, le terrain fait le bord. Rend les mailles
// touchées et le niveau de débordement.
function digPond(out, base, cols, rows, cellSize, design) {
  const { x, y } = design.center
  const radius = design.radius ?? 5
  const depth = design.depth ?? 1
  const berm = design.berm ?? 0.3
  const ring = 2
  const level = heightAt(base, cols, rows, cellSize, x, y)
  const touched = []
  const outer = radius + ring
  const c0 = Math.max(0, Math.floor((x - outer) / cellSize))
  const c1 = Math.min(cols - 1, Math.ceil((x + outer) / cellSize))
  const r0 = Math.max(0, Math.floor((y - outer) / cellSize))
  const r1 = Math.min(rows - 1, Math.ceil((y + outer) / cellSize))
  for (let r = r0; r <= r1; r++) {
    for (let c = c0; c <= c1; c++) {
      const d = Math.hypot(c * cellSize - x, r * cellSize - y)
      const i = r * cols + c
      if (d <= radius) {
        out[i] = Math.min(out[i], level - depth * (1 - (d / radius) ** 2))
        touched.push(i)
      } else if (d <= outer) {
        out[i] = Math.max(out[i], level + berm)
        touched.push(i)
      }
    }
  }
  return { touched, level }
}

// Le relief avec les aménagements creusés, et pour chacun ses mailles et sa
// capacité (m³ d'eau qu'il retient avant de déborder).
export function applyDesigns(base, cols, rows, cellSize, designs) {
  const out = Float32Array.from(base)
  const footprints = []
  for (const design of designs) {
    if (design.type === 'pond') {
      const { touched } = digPond(out, base, cols, rows, cellSize, design)
      footprints.push({ id: design.id, cells: touched })
    } else {
      footprints.push({ id: design.id, cells: digSwale(out, base, cols, rows, cellSize, design) })
    }
  }
  for (const footprint of footprints) footprint.capacity = capacity(out, cols, rows, cellSize, footprint.cells)
  return { heights: out, footprints }
}

// Ce qu'une empreinte retient avant de déborder. On remplit depuis sa maille
// la plus basse en avançant toujours par la maille la plus basse du bord ; la
// première maille HORS empreinte qu'on atteint est le déversoir : le plan d'eau
// s'arrête à sa hauteur (ou au seuil déjà franchi s'il est plus haut). Le
// volume sous ce plan, maille noyée par maille noyée, est la capacité (m³).
export function capacity(heights, cols, rows, cellSize, cells) {
  if (!cells.length) return 0
  const inside = new Set(cells)
  let start = cells[0]
  for (const i of inside) if (heights[i] < heights[start]) start = i
  const seen = new Set([start])
  const frontier = [start]
  const flooded = []
  let level = heights[start]
  let spill = null
  while (frontier.length && flooded.length < 200000) {
    let lowest = 0
    for (let k = 1; k < frontier.length; k++) if (heights[frontier[k]] < heights[frontier[lowest]]) lowest = k
    const i = frontier[lowest]
    frontier[lowest] = frontier[frontier.length - 1]
    frontier.pop()
    if (!inside.has(i)) {
      spill = Math.max(level, heights[i])
      break
    }
    if (heights[i] > level) level = heights[i]
    flooded.push(i)
    const c = i % cols
    const r = (i - c) / cols
    for (const [dc, dr] of [[1, 0], [-1, 0], [0, 1], [0, -1]]) {
      const cc = c + dc
      const rr = r + dr
      if (cc < 0 || rr < 0 || cc >= cols || rr >= rows) continue
      const j = rr * cols + cc
      if (!seen.has(j)) { seen.add(j); frontier.push(j) }
    }
  }
  const surface = spill ?? level
  let volume = 0
  for (const i of flooded) if (surface > heights[i]) volume += (surface - heights[i]) * cellSize * cellSize
  return volume
}

// La grille de simulation (blocs de `factor` × `factor`) d'un relief creusé.
// Un bloc qui touche une tranchée ou une cuvette prend le FOND creusé le plus
// bas du bloc, un bloc de butte sa CRÊTE, les autres la moyenne du terrain.
// Moyenner le terrain autour d'une tranchée faisait remonter son fond de dizaines
// de centimètres d'un bloc à l'autre : une keyline à 1 % (2 cm par bloc)
// devenait un chapelet de poches qui gardaient l'eau au lieu de la mener.
export function downsampleDesigned(base, designed, cols, rows, factor) {
  const outCols = Math.floor(cols / factor)
  const outRows = Math.floor(rows / factor)
  const out = new Float32Array(outCols * outRows)
  for (let r = 0; r < outRows; r++) {
    for (let c = 0; c < outCols; c++) {
      let sum = 0
      let dug = Infinity
      let raised = -Infinity
      for (let dr = 0; dr < factor; dr++) {
        for (let dc = 0; dc < factor; dc++) {
          const i = (r * factor + dr) * cols + c * factor + dc
          sum += base[i]
          if (designed[i] < base[i] && designed[i] < dug) dug = designed[i]
          if (designed[i] > base[i] && designed[i] > raised) raised = designed[i]
        }
      }
      out[r * outCols + c] = dug < Infinity ? dug : raised > -Infinity ? raised : sum / (factor * factor)
    }
  }
  return out
}
