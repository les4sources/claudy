# Issue #247 — partages de revenus. La tiny house appartient à une famille
# tierce : les 4 Sources encaissent la location et reversent la moitié tous les
# trimestres. Le modèle est GÉNÉRIQUE (décision 1) — un accord par hébergement
# partagé, la périodicité est un réglage, pas un autre code.
class CreateRevenueShareAgreements < ActiveRecord::Migration[8.1]
  def change
    create_table :revenue_share_agreements do |t|
      t.references :lodging, null: false, foreign_key: true
      t.string  :beneficiary_name, null: false
      t.string  :beneficiary_email
      t.text    :beneficiary_iban
      t.references :beneficiary_third_party, foreign_key: { to_table: :third_parties }
      t.integer :share_percent, null: false, default: 50
      t.string  :period,        null: false, default: "quarterly"
      t.date    :starts_on,     null: false
      t.date    :ends_on
      t.boolean :active, null: false, default: true
      t.datetime :deleted_at

      t.timestamps
    end

    add_index :revenue_share_agreements, :deleted_at
    add_index :revenue_share_agreements, :active
  end
end
