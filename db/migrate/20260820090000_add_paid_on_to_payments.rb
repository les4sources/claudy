# Date d'ENCAISSEMENT réelle du paiement (Michael 2026-08-20). Jusqu'ici la
# seule date d'un paiement était son `created_at` — la date de SAISIE. La
# secrétaire pointe le compte bancaire avec du retard : un virement reçu le 3
# encodé le 17 apparaissait au 17, ce qui rend le rapprochement administratif
# faux. La colonne est optionnelle ; vide = on retombe sur `created_at`
# (cf. `Payment#effective_date`), donc aucun backfill n'est nécessaire.
class AddPaidOnToPayments < ActiveRecord::Migration[8.1]
  def change
    add_column :payments, :paid_on, :date
  end
end
