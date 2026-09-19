# Le serveur de tuiles du domaine (epic #348, phase 1).
#
# Les tuiles ne sont NI dans le dépôt (120 Mo de binaires dans un dépôt public,
# décision 13) NI chez un tiers : l'orthophoto de 2023 vivait chez Maps Made
# Easy, dont on n'a plus le compte — c'est exactement le genre de dépendance
# qu'on remplace ici. Elles sont sous `storage/map-tiles/`, dossier qui survit
# aux déploiements, et Claudy les sert lui-même.
class MapTilesController < BaseController
  # Une tuile est immuable : son contenu ne change jamais pour un (key, z, x, y)
  # donné. Un an de cache, et le navigateur ne redemande plus rien.
  CACHE_CONTROL = "public, max-age=31536000, immutable".freeze

  def show
    layer = MapBaseLayer.find_by(key: params[:key])
    return head :not_found if layer.nil?
    return head :not_found unless MapBaseLayer::KINDS.include?(params[:kind])

    path = tile_path(layer)
    # Une tuile absente est NORMALE en bord d'emprise : Leaflet en demande tout
    # un carré, le vol n'en couvre qu'une partie. 404, jamais 500 — une erreur
    # serveur ici remplirait Sentry de bruit à chaque déplacement de la carte.
    return head :not_found if path.nil? || !File.file?(path)

    response.set_header("Cache-Control", CACHE_CONTROL)
    send_file path, type: "image/png", disposition: "inline"
  end

  private

  # Le chemin n'est construit qu'à partir d'ENTIERS et d'une clé déjà validée
  # en base : aucun segment ne vient tel quel de l'URL, donc aucun `..` ne peut
  # remonter hors de `storage/map-tiles/`.
  def tile_path(layer)
    z, x, y = [params[:z], params[:x], params[:y]].map { |v| Integer(v, exception: false) }
    return nil if z.nil? || x.nil? || y.nil?
    return nil if z.negative? || x.negative? || y.negative?

    layer.tiles_root.join(params[:kind], z.to_s, x.to_s, "#{y}.png").to_s
  end

  def set_presenters
    @menu_presenter = Components::MenuPresenter.new(active_primary: "map")
  end
end
