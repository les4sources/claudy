class AddSettlementToConsignmentReports < ActiveRecord::Migration[8.1]
  def change
    # Le taux FIGÉ à la vérification. Le contrat d'un artisan peut changer ;
    # un relevé vérifié doit rester relisible avec le taux qui lui a été appliqué.
    add_column :consignment_reports, :commission_percent, :integer

    # L'entité qui porte l'écriture. Nullable : les relevés existants n'en ont
    # pas, et elle n'est exigée qu'au règlement.
    add_reference :consignment_reports, :legal_entity, foreign_key: true, null: true

    # Mode `invoice` : la facture d'achat que l'artisan a envoyée. C'est son
    # paiement qui solde le relevé.
    add_reference :consignment_reports, :purchase_invoice, foreign_key: true, null: true

    add_column :consignment_reports, :settled_on, :date
    add_column :consignment_reports, :posted_at, :datetime
  end
end
