# Le client signale, depuis la page de son séjour, qu'il a envoyé un virement
# (Michael, 2026-10-19). On garde la date et le montant annoncés : la page dit
# « virement signalé » au lieu de reproposer le bouton, et un second clic
# n'envoie pas un second email à la compta.
class AddTransferNoticeToStays < ActiveRecord::Migration[8.1]
  def change
    add_column :stays, :transfer_notified_at, :datetime
    add_column :stays, :transfer_notified_cents, :integer
  end
end
