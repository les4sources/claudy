# L'IBAN d'un membre (epic #241, phase 1). Chiffré au repos comme celui d'un
# tiers : une coordonnée bancaire n'a pas à être lisible dans un dump de base.
# Le champ est donc large — le chiffrement déterministe de Rails encode en
# base64 et dépasse la longueur d'un IBAN en clair.
class AddIbanToHumans < ActiveRecord::Migration[8.1]
  def change
    add_column :humans, :iban, :string
  end
end
