require "rails_helper"
# == Schema Information
#
# Table name: allocation_rules
#
#  id                         :bigint           not null, primary key
#  accepted_count             :integer          default(0), not null
#  active                     :boolean          default(TRUE), not null
#  communication_contains     :string
#  confidence                 :integer          default(80), not null
#  counterparty_iban          :string
#  counterparty_name_contains :string
#  deleted_at                 :datetime
#  direction                  :string
#  label                      :string           not null
#  max_amount_cents           :bigint
#  min_amount_cents           :bigint
#  position                   :integer          default(0), not null
#  rejected_count             :integer          default(0), not null
#  transaction_code           :string
#  created_at                 :datetime         not null
#  updated_at                 :datetime         not null
#  analytic_account_id        :bigint
#  cash_account_id            :bigint
#  event_id                   :bigint
#  general_account_id         :bigint           not null
#  legal_entity_id            :bigint           not null
#  team_id                    :bigint
#
# Indexes
#
#  index_allocation_rules_on_analytic_account_id  (analytic_account_id)
#  index_allocation_rules_on_cash_account_id      (cash_account_id)
#  index_allocation_rules_on_deleted_at           (deleted_at)
#  index_allocation_rules_on_event_id             (event_id)
#  index_allocation_rules_on_general_account_id   (general_account_id)
#  index_allocation_rules_on_legal_entity_id      (legal_entity_id)
#  index_allocation_rules_on_position             (position)
#  index_allocation_rules_on_team_id              (team_id)
#
# Foreign Keys
#
#  fk_rails_...  (analytic_account_id => analytic_accounts.id)
#  fk_rails_...  (cash_account_id => cash_accounts.id)
#  fk_rails_...  (event_id => events.id)
#  fk_rails_...  (general_account_id => general_accounts.id)
#  fk_rails_...  (legal_entity_id => legal_entities.id)
#  fk_rails_...  (team_id => teams.id)
#
require Rails.root.join("spec/support/finance_builders")

# Une règle sans critère est le compte par défaut déguisé : elle s'appliquerait
# à tout. C'est le seul refus vraiment structurant de ce modèle.
RSpec.describe AllocationRule do
  include FinanceBuilders

  let(:entity) { build_legal_entity }
  let!(:fiscal_year) { build_fiscal_year(entity) }
  let(:bank_account) { build_general_account(code: "550000", name: "Banque") }
  let(:charges) { build_general_account(code: "612000", name: "Énergie", klass: 6, nature: "expense") }
  let(:cash_account) { build_cash_account(entity, bank_account) }

  def rule(attributes = {})
    described_class.new({ label: "Énergie", general_account: charges, legal_entity: entity }.merge(attributes))
  end

  it "refuse une règle sans aucun critère" do
    sans_critere = rule

    expect(sans_critere).not_to be_valid
    expect(sans_critere.errors.full_messages.join).to match(/s'appliquerait à tout/i)
  end

  it "accepte une règle avec un seul critère" do
    expect(rule(counterparty_name_contains: "ENGIE")).to be_valid
  end

  describe "la correspondance" do
    let(:entry) do
      build_cash_entry(cash_account, amount_cents: -12_000, label: "Facture énergie").tap do |e|
        e.update!(counterparty_name: "ENGIE ELECTRABEL", counterparty_iban: "BE11222233334444",
                  communication: "FACTURE 2026-08")
      end
    end

    it "rend un motif lisible quand elle correspond" do
      motif = rule(counterparty_name_contains: "engie").match(entry)

      expect(motif).to include("Énergie").and include("engie")
    end

    it "ne correspond pas si un seul critère échoue — ils sont cumulatifs" do
      regle = rule(counterparty_name_contains: "ENGIE", communication_contains: "INTROUVABLE")

      expect(regle.match(entry)).to be_nil
    end

    it "filtre par sens du mouvement" do
      expect(rule(direction: "outgoing", counterparty_name_contains: "ENGIE").match(entry)).to be_present
      expect(rule(direction: "incoming", counterparty_name_contains: "ENGIE").match(entry)).to be_nil
    end

    it "filtre par fourchette de montant, sur la valeur absolue" do
      expect(rule(min_amount_cents: 10_000, counterparty_name_contains: "ENGIE").match(entry)).to be_present
      expect(rule(min_amount_cents: 50_000, counterparty_name_contains: "ENGIE").match(entry)).to be_nil
    end

    it "compare les IBAN sans se laisser tromper par les espaces" do
      expect(rule(counterparty_iban: "BE11 2222 3333 4444").match(entry)).to be_present
    end
  end

  # Issue #392 — une règle propre au compte Beobank de la SRL ne doit plus
  # recouvrir les lignes de la Fondation.
  describe "la restriction à un compte de trésorerie" do
    let(:autre_compte) { build_cash_account(entity, bank_account, name: "Beobank SRL") }

    def ligne(compte)
      build_cash_entry(compte, amount_cents: -12_000, label: "Domiciliation").tap do |e|
        e.update!(communication: "DOMICILIATION EUROPEENNE")
      end
    end

    it "ne correspond pas à une ligne d'un autre compte" do
      regle = rule(communication_contains: "domiciliation", cash_account: autre_compte)

      expect(regle.match(ligne(cash_account))).to be_nil
    end

    it "correspond à une ligne du bon compte et nomme le compte dans le motif" do
      regle = rule(communication_contains: "domiciliation", cash_account: autre_compte)

      expect(regle.match(ligne(autre_compte))).to include("compte Beobank SRL")
    end

    it "laisse une règle sans compte valable partout, motif inchangé" do
      regle = rule(communication_contains: "domiciliation")

      expect(regle.match(ligne(cash_account))).to eq("Règle « Énergie » : la communication contient « domiciliation ».")
      expect(regle.match(ligne(autre_compte))).to be_present
    end

    it "refuse une règle qui ne tiendrait que par son compte" do
      regle = rule(cash_account: autre_compte)

      expect(regle).not_to be_valid
      expect(regle.errors.full_messages.join).to match(/s'appliquerait à tout/)
        .and match(/ne suffit pas à la définir/)
    end

    it "ne reconnaît rien si une telle règle existe malgré tout en base" do
      regle = rule(cash_account: autre_compte)
      regle.save!(validate: false)

      expect(regle.match(ligne(autre_compte))).to be_nil
    end
  end
end
