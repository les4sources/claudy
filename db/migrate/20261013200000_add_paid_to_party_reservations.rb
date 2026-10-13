# Une Pizza Party saisie en admin sur Tranches de Vie se règle SUR PLACE : elle
# reste « non payée » là-bas jusqu'à ce que le boulanger pointe sa caisse, donc
# souvent après le séjour. Claudy ne proposait que les parties déjà payées et
# ces parties-là restaient impossibles à rattacher (Michael, 2026-10-13).
# Les rattachements existants étaient tous payés : ils partent à true.
class AddPaidToPartyReservations < ActiveRecord::Migration[8.1]
  def change
    add_column :party_reservations, :paid, :boolean, null: false, default: true
  end
end
