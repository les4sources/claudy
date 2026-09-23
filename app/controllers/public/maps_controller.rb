module Public
  # La carte du domaine pour les hôtes (epic #348, phase 4).
  #
  # Elle remplace la carte papier remise à l'arrivée (décision 3) : où l'on peut
  # aller, où l'on ne va pas, où l'on demande d'abord, et les points utiles —
  # parking, poubelles, bois, four, épicerie… Elle s'ouvre depuis « Mon séjour »,
  # protégée par le même jeton, sans compte.
  #
  # Ce qui sort d'ici est volontairement étroit : le fond de carte par défaut, la
  # couche Accueil dans la langue du séjour, et le tracé du ou des gîtes de CE
  # séjour. Ni la Gestion (consignes internes), ni les plantes, ni la carte du
  # jour — aucune donnée d'un autre séjour.
  class MapsController < Public::BaseController
    layout "public_stay"

    def show
      stay = Stay.find_by!(token: params[:token])
      @stay = stay.decorate
      @map_page = true
      @base_layer = MapBaseLayer.default_layer
      @welcome = welcome_geojson
      @lodgings = Maps::StayLodgings.new(stay).as_geojson
    rescue ActiveRecord::RecordNotFound
      raise ActionController::RoutingError, "Not Found"
    end

    private

    def welcome_geojson
      layer = MapLayer.find_by(kind: "welcome")
      features = layer ? layer.map_features.ordered.map { |feature| feature.as_public_geojson(I18n.locale) } : []
      { type: "FeatureCollection", features: features }
    end
  end
end
