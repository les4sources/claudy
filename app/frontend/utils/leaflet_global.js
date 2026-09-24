// Leaflet exposé en global AVANT Geoman (epic #348, phase 2).
//
// Geoman 2.x s'accroche à `window.L` et n'équipe que les cartes créées APRÈS
// son chargement (init hook). Ce module est donc importé en premier : les
// imports ES s'évaluent dans l'ordre, Geoman trouve `L` et la carte naît avec
// son `map.pm`.
import L from 'leaflet';

window.L = window.L || L;

export default L;
