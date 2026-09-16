require "rails_helper"
require Rails.root.join("spec/support/finance_builders")

# Epic #250, phase 2 — rapprocher une ligne bancaire de son versement Stripe.
#
# Deux chemins, et c'est tout l'objet de l'epic : en mode `ledger` les recettes
# sont déjà au journal (une seule allocation sur 580000, le virement interne),
# en mode `per_payout` la ligne bancaire EST la recette (ventilation complète).
RSpec.describe Finance::RecordStripePayoutReconciliation do
  include FinanceBuilders

  let!(:entity) { build_legal_entity }
  let!(:fiscal_year) { build_fiscal_year(entity) }
  let!(:banque_compte) { build_general_account(code: "550000", name: "Banque") }
  let!(:stripe_compte) { build_general_account(code: "551000", name: "Stripe") }
  let!(:transferts) { build_general_account(code: "580000", name: "Virements internes", klass: 5, nature: "asset") }
  let!(:hebergement) { build_general_account(code: "700000", name: "Hébergement", klass: 7, nature: "revenue") }
  let!(:frais) { build_general_account(code: "618000", name: "Frais bancaires", klass: 6, nature: "expense") }
  let!(:revenue_mapping) { RevenueMapping.create!(category: "lodging", general_account: hebergement) }
  let!(:banque) { build_cash_account(entity, banque_compte) }

  def stripe_account(mode:)
    CashAccount.create!(name: "Stripe #{mode}", kind: "stripe", legal_entity: entity,
                        general_account: stripe_compte, stripe_account_key: "claudy",
                        stripe_mode: mode)
  end

  def versement(compte, amount_cents: 126_900)
    StripePayout.create!(account_key: "claudy", cash_account: compte, stripe_id: "po_1",
                         amount_cents: amount_cents, arrival_date: Date.new(2026, 6, 15))
  end

  def ligne(amount_cents: 126_900)
    build_cash_entry(banque, amount_cents: amount_cents, entry_date: Date.new(2026, 6, 15),
                     label: "STRIPE PAYOUT")
  end

  describe "en mode grand livre" do
    let(:compte) { stripe_account(mode: "ledger") }

    it "n'écrit QUE le virement interne : les recettes sont déjà au journal" do
      po = versement(compte)
      entry = ligne

      described_class.new(stripe_payout: po, cash_entry: entry).run!

      allocation = entry.reload.cash_allocations.sole
      expect(allocation.general_account).to eq(transferts)
      expect(allocation.document).to eq(po)
      expect(allocation.amount_cents).to eq(126_900)
    end

    it "comptabilise la ligne une fois entièrement affectée" do
      described_class.new(stripe_payout: versement(compte), cash_entry: ligne.tap { |e| @entry = e }).run!

      expect(@entry.reload).to be_posted
    end
  end

  # Le mode « par versement » demanderait une ventilation ALGÉBRIQUE (recettes
  # positives moins commissions négatives) sur une seule ligne. `CashAllocation`
  # la refuse : `same_direction_as_entry` interdit le sens contraire et
  # `within_entry_amount` interdit de dépasser le montant de la ligne. Lever ce
  # garde-fou touche toutes les affectations de l'application, sur de l'argent —
  # la question est posée sur l'epic #250 plutôt que tranchée ici.
  describe "en mode par versement" do
    let(:compte) { stripe_account(mode: "per_payout") }

    it "refuse explicitement, en disant quoi faire" do
      po = versement(compte)
      StripeBalanceTransaction.create!(stripe_payout: po, stripe_id: "txn_1", kind: "charge",
                                       gross_cents: 130_000, fee_cents: 3_100, net_cents: 126_900)

      expect { described_class.new(stripe_payout: po, cash_entry: ligne).run! }
        .to raise_error(described_class::PerPayoutUnsupported, /à la main|mode grand livre/)
    end

    it "n'écrit rien du tout en refusant" do
      po = versement(compte)

      expect {
        begin
          described_class.new(stripe_payout: po, cash_entry: ligne).run!
        rescue described_class::PerPayoutUnsupported
          nil
        end
      }.not_to change(CashAllocation, :count)
    end
  end

  describe "ce qu'il refuse" do
    let(:compte) { stripe_account(mode: "ledger") }

    it "refuse une ligne SORTANTE" do
      expect { described_class.new(stripe_payout: versement(compte), cash_entry: ligne(amount_cents: -126_900)).run! }
        .to raise_error(described_class::WrongDirection)
    end

    it "refuse un montant qui ne correspond pas" do
      expect { described_class.new(stripe_payout: versement(compte), cash_entry: ligne(amount_cents: 126_800)).run! }
        .to raise_error(described_class::AmountMismatch)
    end

    # Rapprocher deux fois le même versement, c'est encaisser deux fois.
    it "refuse un versement déjà rapproché" do
      po = versement(compte)
      described_class.new(stripe_payout: po, cash_entry: ligne).run!

      expect { described_class.new(stripe_payout: po, cash_entry: ligne).run! }
        .to raise_error(described_class::AlreadyReconciled)
    end
  end
end
