# Certains porteurs ne sont pas payés directement : la SPRL Domaine d'Ahinvaux
# facture la Fondation à 40 €/h et leur verse leur part (Michael, 2026-10-13,
# « À la SRL »). Le membre dit par qui passe sa rémunération ; le relevé, émis
# au nom de la SRL, garde ce tiers même si le réglage change ensuite.
class AddCarrierPayeeToHumans < ActiveRecord::Migration[8.1]
  def change
    add_reference :humans, :carrier_payee, foreign_key: { to_table: :third_parties }, null: true
    add_reference :carrier_statements, :third_party, foreign_key: true, null: true
  end
end
