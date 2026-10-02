module Unifi
  # Un équipement UniFi tel que la carte en a besoin (epic #348, phase 10),
  # normalisé depuis la réponse de l'API Site Manager. `status` vaut
  # "online", "offline" ou nil quand l'API ne le dit pas ; `last_seen_at` est
  # la dernière remontée de l'hôte qui le porte.
  Device = Struct.new(:id, :mac, :name, :model, :ip, :status, :last_seen_at, :host_name, keyword_init: true) do
    def online? = status == "online"

    # « Switch grange — USW Flex Mini (F4E2C6C23F13) », pour la liste de choix.
    def label
      [name, ("— #{model}" if model.present? && model != name), ("(#{mac})" if mac.present?)].compact.join(" ")
    end

    def as_json(*)
      to_h.merge(last_seen_at: last_seen_at&.iso8601, label: label).as_json
    end
  end
end
