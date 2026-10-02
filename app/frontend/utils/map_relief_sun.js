// Le soleil sur le relief de la vue 3D (`/map/relief`) : où porte l'ombre à une
// heure donnée, et combien d'heures de soleil direct chaque mètre carré reçoit
// sur une journée.
//
// Les ombres se calculent sur le modèle de SURFACE du SPW (arbres, haies et
// toits compris), pas sur le terrain nu : c'est la canopée qui fait l'ombre d'un
// jardin-forêt. Comme `map_relief_hydro.js`, ce module n'importe rien (ni
// three.js ni DOM) pour qu'on puisse l'exercer seul.

const RAD = Math.PI / 180
const DAY_MS = 86400000
const J1970 = 2440588
const J2000 = 2451545
const OBLIQUITY = RAD * 23.4397

// Position du soleil, d'après les formules de SunCalc (V. Agafonkin, d'après
// les « Astronomy Answers » de l'Observatoire de Leyde) : précises à quelques
// dixièmes de degré, bien assez pour une ombre au mètre près.
//
// Renvoie `azimuth` en radians depuis le NORD, dans le sens horaire (π/2 = est),
// et `altitude` en radians au-dessus de l'horizon.
export function sunPosition(date, lat, lng) {
  const days = date.valueOf() / DAY_MS - 0.5 + J1970 - J2000
  const anomaly = RAD * (357.5291 + 0.98560028 * days)
  const center = RAD * (1.9148 * Math.sin(anomaly) + 0.02 * Math.sin(2 * anomaly) + 0.0003 * Math.sin(3 * anomaly))
  const longitude = anomaly + center + RAD * 102.9372 + Math.PI
  const declination = Math.asin(Math.sin(longitude) * Math.sin(OBLIQUITY))
  const ascension = Math.atan2(Math.sin(longitude) * Math.cos(OBLIQUITY), Math.cos(longitude))
  const hourAngle = RAD * (280.16 + 360.9856235 * days) + RAD * lng - ascension
  const phi = RAD * lat
  const altitude = Math.asin(Math.sin(phi) * Math.sin(declination) +
                             Math.cos(phi) * Math.cos(declination) * Math.cos(hourAngle))
  // SunCalc compte l'azimut depuis le SUD vers l'ouest ; + π le ramène au nord.
  const fromSouth = Math.atan2(Math.sin(hourAngle),
                               Math.cos(hourAngle) * Math.sin(phi) - Math.tan(declination) * Math.cos(phi))
  return { azimuth: (fromSouth + Math.PI) % (2 * Math.PI), altitude }
}

// L'ombre à un instant : 1 = au soleil, 0 = à l'ombre (portée par le relief, un
// arbre, un toit, ou la pente elle-même quand elle tourne le dos au soleil).
//
// Un balayage en un seul passage : on parcourt la grille en partant du côté du
// soleil, et chaque maille hérite de la « hauteur d'ombre » de sa voisine côté
// soleil, abaissée de la pente du rayon (distance × tan(hauteur du soleil)).
// Si cette hauteur dépasse la surface, la maille est à l'ombre ; sinon c'est la
// surface qui devient la nouvelle hauteur d'ombre. La voisine tombe rarement
// pile sur une maille : on interpole entre les deux plus proches.
//
// `surface` : hauteurs (m), lignes du nord au sud. `out` : Uint8Array réutilisé.
export function shadowMask(surface, cols, rows, cellSize, sun, out = new Uint8Array(cols * rows), level = new Float32Array(cols * rows)) {
  if (sun.altitude <= 0) {
    out.fill(0)
    return out
  }
  // Vers le soleil, en mailles : +x à l'est, +y au sud (les lignes descendent).
  const ux = Math.sin(sun.azimuth)
  const uy = -Math.cos(sun.azimuth)
  const slope = Math.tan(sun.altitude)
  const epsilon = 0.05

  if (Math.abs(ux) >= Math.abs(uy)) {
    const dc = ux > 0 ? 1 : -1
    const dr = uy / Math.abs(ux)
    const drop = cellSize * Math.hypot(1, dr) * slope
    const start = dc > 0 ? cols - 1 : 0
    for (let c = start; c >= 0 && c < cols; c -= dc) {
      const up = c + dc
      for (let r = 0; r < rows; r++) {
        const i = r * cols + c
        const height = surface[i]
        let shade = -Infinity
        if (up >= 0 && up < cols) {
          const rr = r + dr
          const r0 = Math.floor(rr)
          if (r0 >= 0 && r0 + 1 < rows) {
            const f = rr - r0
            shade = level[r0 * cols + up] * (1 - f) + level[(r0 + 1) * cols + up] * f - drop
          } else if (r0 >= 0 && r0 < rows) {
            shade = level[r0 * cols + up] - drop
          }
        }
        out[i] = shade > height + epsilon ? 0 : 1
        level[i] = shade > height ? shade : height
      }
    }
  } else {
    const dr = uy > 0 ? 1 : -1
    const dc = ux / Math.abs(uy)
    const drop = cellSize * Math.hypot(1, dc) * slope
    const start = dr > 0 ? rows - 1 : 0
    for (let r = start; r >= 0 && r < rows; r -= dr) {
      const up = r + dr
      for (let c = 0; c < cols; c++) {
        const i = r * cols + c
        const height = surface[i]
        let shade = -Infinity
        if (up >= 0 && up < rows) {
          const cc = c + dc
          const c0 = Math.floor(cc)
          if (c0 >= 0 && c0 + 1 < cols) {
            const f = cc - c0
            shade = level[up * cols + c0] * (1 - f) + level[up * cols + c0 + 1] * f - drop
          } else if (c0 >= 0 && c0 < cols) {
            shade = level[up * cols + c0] - drop
          }
        }
        out[i] = shade > height + epsilon ? 0 : 1
        level[i] = shade > height ? shade : height
      }
    }
  }
  return out
}

// Les heures de soleil direct de chaque maille sur une journée, échantillonnée
// tous les `stepMinutes`. `day` : n'importe quel instant du jour voulu, en
// heure locale du navigateur. Rend aussi la durée du jour (soleil levé).
//
// Le calcul s'interrompt toutes les quelques passes (`await`) pour laisser la
// page respirer ; `onProgress(fraction)` suit l'avancement.
export async function sunHours(surface, cols, rows, cellSize, lat, lng, day, { stepMinutes = 15, onProgress } = {}) {
  const hours = new Float32Array(cols * rows)
  const mask = new Uint8Array(cols * rows)
  const level = new Float32Array(cols * rows)
  const base = new Date(day.getFullYear(), day.getMonth(), day.getDate(), 0, 0, 0)
  const step = stepMinutes / 60
  const samples = Math.round(24 / step)
  let daylight = 0
  for (let k = 0; k < samples; k++) {
    // Le milieu de chaque intervalle représente l'intervalle.
    const at = new Date(base.valueOf() + (k + 0.5) * step * 3600000)
    const sun = sunPosition(at, lat, lng)
    if (sun.altitude > 0) {
      daylight += step
      shadowMask(surface, cols, rows, cellSize, sun, mask, level)
      for (let i = 0; i < mask.length; i++) if (mask[i]) hours[i] += step
    }
    if (k % 6 === 5) {
      onProgress?.(k / samples)
      await new Promise((resolve) => setTimeout(resolve, 0))
    }
  }
  return { hours, daylight }
}
