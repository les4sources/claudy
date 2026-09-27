# Le statut UniFi en direct (epic #348, phase 10). La carte interroge cet
# endpoint toutes les 60 s tant que la couche Ethernet est affichée, pour
# colorer les pastilles de ses nœuds UniFi.
#
# Il répond toujours 200 : sans clé ou quand l'API ne répond pas, il le dit
# (`configured`, `available`) et la carte grise ses pastilles. Le client garde
# la réponse 60 s en cache, l'API n'est pas interrogée à chaque rafraîchissement.
class MapUnifiController < BaseController
  def devices
    client = Unifi::Client.new
    render json: { configured: client.configured?, available: client.available?, devices: client.devices.as_json }
  end

  private

  def set_presenters
    @menu_presenter = Components::MenuPresenter.new(active_primary: "map")
  end
end
