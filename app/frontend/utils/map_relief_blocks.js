// Le relief en blocs (`/map/relief`, fond « Blocs ») : le domaine en cubes de
// 2 m, façon jeu de construction. Herbe, chemins, eau et sol forestier selon
// l'occupation du sol ; arbres (feuillage, troncs aux cimes) et bâtiments
// (murs, toit) tirés du modèle de surface, à leur vraie hauteur.
//
// Les cubes restent cubiques à l'écran quelle que soit l'exagération : le
// relief est quantifié en hauteur AFFICHÉE (exagérée), un étage vaut un bloc.
// Ce qui dépasse du sol (arbres, toits) compte en vrais mètres, comme ailleurs
// sur la vue.
//
// `buildBlocks` ne dépend ni de three.js ni du DOM : il rend des tableaux
// (positions, normales, coordonnées de texture en blocs, numéro de tuile) que
// la scène habille. Les faces cachées ne sont pas émises ; les dessus contigus
// d'une même rangée et les flancs d'une même colonne sont fusionnés.

export const TILES = {
  grass: 0, grassSide: 1, dirt: 2, stone: 3, gravel: 4, water: 5, podzol: 6, podzolSide: 7,
  leaves: 8, log: 9, logTop: 10, planks: 11, roof: 12,
}
export const ATLAS_COLUMNS = 8
export const ATLAS_ROWS = 2

const FOREST = new Set([8, 9, 80, 90])
const NONE = 0
const BUILDING = 1
const TREE = 2
const SHRUB = 3

// Le sol d'un bloc selon l'occupation du sol (WalOUS) : [dessus, flanc de la
// première couche].
function groundTiles(landcover) {
  if (landcover === 1 || landcover === 2) return [TILES.gravel, TILES.dirt]
  if (landcover === 5) return [TILES.water, TILES.water]
  if (FOREST.has(landcover)) return [TILES.podzol, TILES.podzolSide]
  return [TILES.grass, TILES.grassSide]
}

// `input` : { ground (altitudes vraies, aménagements creusés), original (MNT
// nu), surface (MNS, ou null), landcover (ou null), cols, rows, cell (m),
// block (m), exaggeration, zBase, x0, z0 (demi-emprise de la scène) }.
export function buildBlocks(input) {
  const { ground, original, surface, landcover, cols, rows, cell, block, exaggeration, zBase, x0, z0 } = input
  const k = Math.max(1, Math.round(block / cell))
  const bc = Math.ceil(cols / k)
  const br = Math.ceil(rows / k)
  const count = bc * br
  const step = block / exaggeration       // un étage dans le repère du groupe exagéré

  const top = new Int16Array(count)        // premier étage vide au-dessus du sol
  const kind = new Uint8Array(count)
  const height = new Uint8Array(count)     // étages au-dessus du sol (arbre, bâtiment)
  const leafStart = new Int16Array(count)
  const trunk = new Uint8Array(count)
  const above = new Float32Array(count)
  const cover = new Uint8Array(count)
  const roof = new Uint8Array(count)
  const built = new Uint8Array(count)      // du bâti (WalOUS) dans le bloc
  let minTop = Infinity

  for (let j = 0; j < br; j++) {
    for (let i = 0; i < bc; i++) {
      let sum = 0
      let n = 0
      let tallest = 0
      let rough = 0
      let roughCount = 0
      for (let r = j * k; r < Math.min(rows, j * k + k); r++) {
        for (let c = i * k; c < Math.min(cols, i * k + k); c++) {
          const index = r * cols + c
          sum += ground[index]
          n++
          if (landcover && landcover[index] === 2) built[j * bc + i] = 1
          if (!surface) continue
          tallest = Math.max(tallest, surface[index] - original[index])
          if (r > 0 && c > 0 && r < rows - 1 && c < cols - 1) {
            rough += Math.abs(4 * surface[index] - surface[index - 1] - surface[index + 1] - surface[index - cols] - surface[index + cols])
            roughCount++
          }
        }
      }
      const b = j * bc + i
      const centre = Math.min(rows - 1, j * k + (k >> 1)) * cols + Math.min(cols - 1, i * k + (k >> 1))
      top[b] = Math.round(((sum / n - zBase) * exaggeration) / block)
      above[b] = tallest
      // Un toit est lisse (un plan, deux pans), un houppier bosselé : la
      // courbure moyenne du MNS les sépare (toits 0,3 à 2 m, forêt ~7 m). Plus
      // sûr que l'occupation du sol, qui classe parfois la cour en bâti et les
      // toits autour en feuillus.
      roof[b] = tallest > 2.5 && tallest < 18 && roughCount > 0 && rough / roughCount < 3 ? 1 : 0
      cover[b] = landcover ? landcover[centre] : 7
      if (top[b] < minTop) minTop = top[b]
    }
  }

  // Un bâtiment a du sol dégagé à quelques mètres ; une plage lisse au cœur
  // d'une forêt (résineux serrés, taillis) n'en a pas : ce n'est pas un toit.
  const isolated = new Uint8Array(count)
  for (let j = 0; j < br; j++) {
    for (let i = 0; i < bc; i++) {
      const b = j * bc + i
      if (!roof[b]) continue
      let open = 0
      for (let dj = -3; dj <= 3; dj++) {
        for (let di = -3; di <= 3; di++) {
          const ni = i + di
          const nj = j + dj
          if (ni >= 0 && nj >= 0 && ni < bc && nj < br && above[nj * bc + ni] < 1) open++
        }
      }
      if (open < 4) isolated[b] = 1
    }
  }
  for (let b = 0; b < count; b++) if (isolated[b]) roof[b] = 0
  // Et un bâtiment fait au moins 24 m² d'un seul tenant (un arbre isolé au
  // houppier lisse n'en fait pas un) et touche, à 6 m près, du bâti de
  // l'occupation du sol (une haie taillée, lisse elle aussi, non). Sans
  // occupation du sol, la taille suffit.
  const nearBuilt = (members) => {
    if (!landcover) return true
    for (const b of members) {
      const i = b % bc
      const j = (b - i) / bc
      for (let dj = -3; dj <= 3; dj++) {
        for (let di = -3; di <= 3; di++) {
          const ni = i + di
          const nj = j + dj
          if (ni >= 0 && nj >= 0 && ni < bc && nj < br && built[nj * bc + ni]) return true
        }
      }
    }
    return false
  }
  const seen = new Uint8Array(count)
  const stack = []
  const members = []
  for (let start = 0; start < count; start++) {
    if (!roof[start] || seen[start]) continue
    members.length = 0
    stack.push(start)
    seen[start] = 1
    while (stack.length) {
      const b = stack.pop()
      members.push(b)
      const i = b % bc
      for (const o of [i > 0 ? b - 1 : -1, i < bc - 1 ? b + 1 : -1, b - bc, b + bc]) {
        if (o >= 0 && o < count && roof[o] && !seen[o]) { seen[o] = 1; stack.push(o) }
      }
    }
    if (members.length * k * k * cell * cell < 24 || !nearBuilt(members)) for (const b of members) roof[b] = 0
  }

  // La canopée lissée sur 5 × 5 blocs : une forêt en plateaux, comme dans le
  // jeu, plutôt qu'une marche à chaque bloc (et quatre fois moins de faces).
  const canopy = new Float32Array(count)
  for (let j = 0; j < br; j++) {
    for (let i = 0; i < bc; i++) {
      const b = j * bc + i
      if (above[b] <= 2.5 || roof[b]) { canopy[b] = above[b]; continue }
      let sum = 0
      let n = 0
      for (let dj = -2; dj <= 2; dj++) {
        for (let di = -2; di <= 2; di++) {
          const ni = i + di
          const nj = j + dj
          if (ni < 0 || nj < 0 || ni >= bc || nj >= br) continue
          const o = nj * bc + ni
          if (above[o] > 2.5 && !roof[o]) { sum += above[o]; n++ }
        }
      }
      canopy[b] = sum / n
    }
  }
  for (let b = 0; b < count; b++) {
    const a = canopy[b]
    if (a > 2.5) {
      kind[b] = roof[b] ? BUILDING : TREE
      height[b] = Math.min(40, Math.max(1, Math.round(a / block)))
    } else if (a >= 1 && cover[b] !== 1 && cover[b] !== 2 && cover[b] !== 5) {
      kind[b] = SHRUB
      height[b] = 1
    }
  }
  // Un tronc sous chaque cime (le plus haut feuillage de son voisinage), le
  // feuillage d'une couronne de 1 à 3 étages par-dessus.
  for (let j = 0; j < br; j++) {
    for (let i = 0; i < bc; i++) {
      const b = j * bc + i
      if (kind[b] !== TREE) continue
      const depth = Math.min(3, Math.max(1, Math.round(height[b] * 0.4)))
      leafStart[b] = top[b] + height[b] - depth
      let peak = true
      for (let dj = -1; dj <= 1 && peak; dj++) {
        for (let di = -1; di <= 1; di++) {
          if (!di && !dj) continue
          const ni = i + di
          const nj = j + dj
          if (ni < 0 || nj < 0 || ni >= bc || nj >= br) continue
          const o = nj * bc + ni
          if (above[o] > above[b] || (above[o] === above[b] && o < b)) { peak = false; break }
        }
      }
      trunk[b] = peak ? 1 : 0
    }
  }

  const floor = minTop - 4
  const columnTop = (b) => (kind[b] === NONE ? top[b] : top[b] + height[b])
  const solid = (b, level) => {
    if (level < floor) return false
    if (level < top[b]) return true
    const k2 = kind[b]
    if (k2 === NONE || level >= top[b] + height[b]) return false
    if (k2 === TREE) return level >= leafStart[b] || trunk[b] === 1
    return true
  }
  // La tuile d'une face selon ce qu'elle habille.
  const sideTile = (b, level) => {
    if (level >= top[b]) {
      if (kind[b] === BUILDING) return TILES.planks
      if (kind[b] === TREE && level < leafStart[b]) return TILES.log
      return TILES.leaves
    }
    const depth = top[b] - 1 - level
    if (depth === 0) return groundTiles(cover[b])[1]
    return depth < 4 ? TILES.dirt : TILES.stone
  }
  const topTile = (b, level) => {
    if (level >= top[b]) {
      if (kind[b] === BUILDING) return TILES.roof
      if (kind[b] === TREE && level < leafStart[b]) return TILES.logTop
      return TILES.leaves
    }
    return level === top[b] - 1 ? groundTiles(cover[b])[0] : TILES.dirt
  }

  const out = new FaceBuffer(Math.max(1 << 16, count * 3))
  const half = cell / 2
  const left = (i) => i * k * cell - half - x0
  const right = (i) => Math.min(cols, (i + 1) * k) * cell - half - x0
  const north = (j) => j * k * cell - half - z0
  const south = (j) => Math.min(rows, (j + 1) * k) * cell - half - z0
  const neighbours = [[1, 0, 0], [-1, 0, 1], [0, 1, 2], [0, -1, 3]]   // +x, -x, +z, -z

  for (let j = 0; j < br; j++) {
    // Les dessus (et les dessous du feuillage) d'une rangée, fusionnés le long
    // de x : sens|étage|tuile → départ.
    const runs = new Map()
    const flush = (key, run) => {
      if (run.up) out.top(left(run.start), right(run.end), north(j), south(j), (run.level + 1) * step, run.tile)
      else out.bottom(left(run.start), right(run.end), north(j), south(j), run.level * step, run.tile)
      runs.delete(key)
    }
    const extend = (i, level, tile, up) => {
      const key = (level * 16 + tile) * 2 + (up ? 1 : 0)
      const run = runs.get(key)
      if (run && run.end === i - 1) { run.end = i; return }
      if (run) flush(key, run)
      runs.set(key, { start: i, end: i, level, tile, up })
    }
    for (let i = 0; i < bc; i++) {
      const b = j * bc + i
      const highest = columnTop(b)

      // Les dessus (et dessous du feuillage flottant).
      for (let level = floor; level < highest; level++) {
        if (level < top[b] - 1) { level = top[b] - 2; continue }
        if (!solid(b, level)) continue
        if (!solid(b, level + 1)) extend(i, level, topTile(b, level), true)
        if (level > floor && level >= top[b] && !solid(b, level - 1)) extend(i, level, topTile(b, level), false)
      }

      // Les flancs, fusionnés le long de la colonne.
      for (const [di, dj, face] of neighbours) {
        const ni = i + di
        const nj = j + dj
        const outside = ni < 0 || nj < 0 || ni >= bc || nj >= br
        const o = outside ? -1 : nj * bc + ni
        const from = outside ? floor : Math.max(floor, Math.min(top[b], top[o]))
        let runStart = null
        let runTile = -1
        const emit = (end) => {
          if (runStart === null) return
          out.side(face, left(i), right(i), north(j), south(j), runStart * step, end * step, end - runStart, runTile)
          runStart = null
        }
        for (let level = from; level < highest; level++) {
          const exposed = solid(b, level) && (outside || !solid(o, level))
          const tile = exposed ? sideTile(b, level) : -1
          if (!exposed || tile !== runTile) emit(level)
          if (exposed && runStart === null) { runStart = level; runTile = tile }
        }
        emit(highest)
      }
    }
    for (const [key, run] of runs) flush(key, run)
  }

  // Le dessus du sol de chaque bloc, dans le repère exagéré : de quoi y poser
  // la Niva et les plantes.
  const groundTops = new Float32Array(count)
  for (let b = 0; b < count; b++) groundTops[b] = top[b] * step

  return { ...out.arrays(), groundTops, cols: bc, rows: br, size: k * cell, faces: out.faces }
}

// Des tableaux typés qui grandissent : quatre sommets et six indices par face.
class FaceBuffer {
  constructor(faces) {
    this.capacity = faces
    this.faces = 0
    this.positions = new Float32Array(faces * 12)
    this.normals = new Int8Array(faces * 12)
    this.uvs = new Uint16Array(faces * 8)
    this.tiles = new Uint8Array(faces * 4)
  }

  grow() {
    this.capacity *= 2
    const copy = (array, Type, per) => { const next = new Type(this.capacity * per); next.set(array); return next }
    this.positions = copy(this.positions, Float32Array, 12)
    this.normals = copy(this.normals, Int8Array, 12)
    this.uvs = copy(this.uvs, Uint16Array, 8)
    this.tiles = copy(this.tiles, Uint8Array, 4)
  }

  // Quatre coins dans l'ordre trigonométrique vu de dehors, leurs coordonnées
  // en blocs, une normale.
  quad(corners, uv, normal, tile) {
    if (this.faces === this.capacity) this.grow()
    const f = this.faces++
    this.positions.set(corners, f * 12)
    this.uvs.set(uv, f * 8)
    for (let v = 0; v < 4; v++) {
      this.normals.set(normal, f * 12 + v * 3)
      this.tiles[f * 4 + v] = tile
    }
  }

  top(xa, xb, za, zb, y, tile) {
    const u = Math.round((xb - xa) / (zb - za)) || 1
    this.quad([xa, y, za, xa, y, zb, xb, y, zb, xb, y, za], [0, 0, 0, 1, u, 1, u, 0], [0, 127, 0], tile)
  }

  bottom(xa, xb, za, zb, y, tile) {
    const u = Math.round((xb - xa) / (zb - za)) || 1
    this.quad([xa, y, za, xb, y, za, xb, y, zb, xa, y, zb], [0, 0, u, 0, u, 1, 0, 1], [0, -127, 0], tile)
  }

  // `face` : 0 = est (+x), 1 = ouest (−x), 2 = sud (+z), 3 = nord (−z) ;
  // `levels` étages de haut, de `ya` à `yb`.
  side(face, xa, xb, za, zb, ya, yb, levels, tile) {
    const uv = [0, 0, 1, 0, 1, levels, 0, levels]
    if (face === 0) this.quad([xb, ya, zb, xb, ya, za, xb, yb, za, xb, yb, zb], uv, [127, 0, 0], tile)
    else if (face === 1) this.quad([xa, ya, za, xa, ya, zb, xa, yb, zb, xa, yb, za], uv, [-127, 0, 0], tile)
    else if (face === 2) this.quad([xa, ya, zb, xb, ya, zb, xb, yb, zb, xa, yb, zb], uv, [0, 0, 127], tile)
    else this.quad([xb, ya, za, xa, ya, za, xa, yb, za, xb, yb, za], uv, [0, 0, -127], tile)
  }

  arrays() {
    const f = this.faces
    const indices = new Uint32Array(f * 6)
    for (let i = 0; i < f; i++) {
      const v = i * 4
      indices.set([v, v + 1, v + 2, v, v + 2, v + 3], i * 6)
    }
    return {
      positions: this.positions.slice(0, f * 12),
      normals: this.normals.slice(0, f * 12),
      uvs: this.uvs.slice(0, f * 8),
      tiles: this.tiles.slice(0, f * 4),
      indices,
    }
  }
}

// ---- Les textures --------------------------------------------------------------
//
// Du pixel art 16 × 16 dessiné ici, au hasard réglé (même graine, même dessin) :
// pas de fichier, rien de copié. Rend la planche et la couleur moyenne de chaque
// tuile (pour fondre les blocs lointains, où 16 pixels deviennent du bruit).

export function blockAtlas() {
  const size = 16
  const canvas = document.createElement('canvas')
  canvas.width = ATLAS_COLUMNS * size
  canvas.height = ATLAS_ROWS * size
  const ctx = canvas.getContext('2d')
  const random = seeded(48151623)
  const pick = (palette) => palette[Math.floor(random() * palette.length)]

  const GRASS = ['#5c8f33', '#518229', '#68a03c', '#4a7726', '#5f9536']
  const DIRT = ['#7b5636', '#6c4a2e', '#87603d', '#5f4229']
  const STONE = ['#7f7f7f', '#737373', '#8b8b8b', '#6a6a6a']
  const GRAVEL = ['#9b9288', '#867d74', '#aba298', '#78716a', '#938a7f']
  const WATER = ['#2f60b4', '#3568c1', '#2b57a4', '#3b6fc7']
  const PODZOL = ['#4f5f2a', '#58592c', '#46592a', '#5a512c', '#516630']
  const LEAVES = ['#2f6c20', '#285d1b', '#3a7b27', '#21501a']
  const BARK = ['#5c4227', '#4b3521', '#6a4c2d', '#553c24']
  const PLANKS = ['#a77e4d', '#9c7446', '#b08752', '#a07849']
  const ROOF = ['#7b3c2f', '#86443a', '#713529', '#8b4a3c']

  const tile = (index, draw) => {
    const ox = (index % ATLAS_COLUMNS) * size
    const oy = Math.floor(index / ATLAS_COLUMNS) * size
    for (let y = 0; y < size; y++) {
      for (let x = 0; x < size; x++) {
        ctx.fillStyle = draw(x, y)
        ctx.fillRect(ox + x, oy + y, 1, 1)
      }
    }
  }
  // La bordure herbeuse d'un flanc : trois rangées, une quatrième frangée.
  const fringe = (palette, under) => (x, y) => (y < 3 || (y === 3 && random() < 0.5) ? pick(palette) : pick(under))

  tile(TILES.grass, () => pick(GRASS))
  tile(TILES.grassSide, fringe(GRASS, DIRT))
  tile(TILES.dirt, () => pick(DIRT))
  tile(TILES.stone, () => (random() < 0.08 ? '#585858' : pick(STONE)))
  tile(TILES.gravel, () => pick(GRAVEL))
  tile(TILES.water, () => (random() < 0.06 ? '#6592da' : pick(WATER)))
  tile(TILES.podzol, () => pick(PODZOL))
  tile(TILES.podzolSide, fringe(PODZOL, DIRT))
  tile(TILES.leaves, () => (random() < 0.14 ? '#183c11' : pick(LEAVES)))
  tile(TILES.log, (x) => (x % 4 === 0 ? '#3f2c1b' : pick(BARK)))
  tile(TILES.logTop, (x, y) => {
    const d = Math.hypot(x - 7.5, y - 7.5)
    if (d > 6.6) return pick(BARK)
    return Math.floor(d) % 2 ? '#a17b4b' : '#8b6739'
  })
  tile(TILES.planks, (x, y) => (y % 4 === 3 || (x === ((Math.floor(y / 4) * 5) % 16)) ? '#6f5333' : pick(PLANKS)))
  tile(TILES.roof, (x, y) => (y % 4 === 3 ? '#5c2b22' : pick(ROOF)))

  const averages = new Float32Array(ATLAS_COLUMNS * ATLAS_ROWS * 3)
  for (let t = 0; t < ATLAS_COLUMNS * ATLAS_ROWS; t++) {
    const data = ctx.getImageData((t % ATLAS_COLUMNS) * size, Math.floor(t / ATLAS_COLUMNS) * size, size, size).data
    let r = 0; let g = 0; let b = 0
    for (let p = 0; p < data.length; p += 4) { r += data[p]; g += data[p + 1]; b += data[p + 2] }
    const n = data.length / 4 * 255
    averages.set([r / n, g / n, b / n], t * 3)
  }
  return { canvas, averages }
}

function seeded(seed) {
  let a = seed >>> 0
  return () => {
    a = (a + 0x6d2b79f5) >>> 0
    let t = a
    t = Math.imul(t ^ (t >>> 15), t | 1)
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61)
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296
  }
}
