# Une Pizza Party peut être réglée AVEC le séjour : le client fait un seul
# virement (séjour + party) aux 4 Sources, et la boulangerie pointe ensuite la
# party « payée ». Le paiement miroir « Tranches de Vie » compterait alors deux
# fois le même argent dans l'encaissé (Michael, 2026-10-19, séjour #1546).
class AddPaidWithStayToPartyReservations < ActiveRecord::Migration[8.1]
  def change
    add_column :party_reservations, :paid_with_stay, :boolean, null: false, default: false
  end
end
