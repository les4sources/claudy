require "rails_helper"
require Rails.root.join("spec/support/finance_builders")

# Rapprocher une ligne entrante d'un séjour choisi à la main, depuis sa fiche
# (Michael, 2026-10-19). La file « À affecter » ne propose un séjour que si la
# cascade de `MatchStay` en trouve un seul, au solde ouvert : un séjour soldé
# par un paiement saisi sur sa fiche, ou deux séjours au même montant, ne
# laissaient aucun geste à l'écran.
RSpec.describe "Comptabilité — rapprocher une ligne d'un séjour choisi", type: :request do
  include Devise::Test::IntegrationHelpers
  include FinanceBuilders

  let(:user) { User.create!(email: "compta-sejour@les4sources.be", password: "password123") }
  let!(:entity) { build_legal_entity(name: "Fondation Les 4 Sources") }
  let!(:fiscal_year) { build_fiscal_year(entity) }
  let!(:banque) { build_general_account(code: "550000", name: "Banque") }
  let!(:compte_bancaire) { build_cash_account(entity, banque) }
  let!(:customer) { Customer.create!(first_name: "Camille", last_name: "Renard", email: "camille@example.org") }
  let!(:stay) do
    Stay.create!(customer: customer, arrival_date: Date.new(2026, 6, 1), departure_date: Date.new(2026, 6, 4),
                 total_amount_cents: 130_000)
  end
  let(:entry) { build_cash_entry(compte_bancaire, amount_cents: 130_000, entry_date: Date.new(2026, 6, 15)) }

  before { sign_in user }

  def stub_quote(lodging:)
    hebergement = build_general_account(code: "700000", name: "Hébergement", klass: 7, nature: "revenue")
    RevenueMapping.find_or_create_by!(category: "lodging") { |m| m.general_account = hebergement }
    quote = instance_double(PricingModel::Quote, lodging_only_cents: lodging, spaces_cents: 0,
                                                 meals_cents: 0, camping_cents: 0, van_cents: 0,
                                                 terrace_cents: 0, hamac_cents: 0, experiences_cents: 0)
    allow(Stays::DraftReconstructor).to receive(:priced).with(stay).and_return(:draft)
    allow(PricingModel).to receive(:quote).with(:draft).and_return(quote)
  end

  describe "la fiche d'une ligne" do
    it "liste les séjours autour de la date, soldés compris, annulés exclus" do
      stay.update_column(:payment_status, "paid")
      annule = Stay.create!(customer: customer, arrival_date: Date.new(2026, 6, 10),
                            departure_date: Date.new(2026, 6, 12), total_amount_cents: 50_000)
      annule.update_column(:status, "canceled")

      get finance_cash_entry_path(entry)

      expect(response.body).to include("Rapprocher d&#39;un séjour")
      expect(response.body).to include("##{stay.id} · Camille Renard · 01/06 → 04/06/2026")
      expect(response.body).to include("soldé")
      expect(response.body).not_to include("##{annule.id} ·")
    end

    it "dit ce qu'une autre ligne a déjà ventilé sur le séjour" do
      autre = build_cash_entry(compte_bancaire, amount_cents: 30_000, entry_date: Date.new(2026, 5, 20))
      hebergement = build_general_account(code: "700000", name: "Hébergement", klass: 7, nature: "revenue")
      autre.cash_allocations.create!(general_account: hebergement, legal_entity: entity, amount_cents: 30_000,
                                     document: stay)

      get finance_cash_entry_path(entry)

      expect(response.body).to include("déjà rapproché 300,00")
    end

    it "présélectionne le séjour que la cascade aurait proposé" do
      entry.update!(communication: "SEJOUR ##{stay.id}")

      get finance_cash_entry_path(entry)

      expect(response.body).to match(/<option selected="selected" value="#{stay.id}">/)
    end

    it "ne propose rien sur une ligne sortante" do
      sortie = build_cash_entry(compte_bancaire, amount_cents: -130_000)

      get finance_cash_entry_path(sortie)

      expect(response.body).not_to include("name=\"stay_id\"")
    end

    it "ne propose rien sur une ligne déjà entamée" do
      hebergement = build_general_account(code: "700000", name: "Hébergement", klass: 7, nature: "revenue")
      entry.cash_allocations.create!(general_account: hebergement, legal_entity: entity, amount_cents: 10_000)

      get finance_cash_entry_path(entry)

      expect(response.body).not_to include("name=\"stay_id\"")
    end
  end

  describe "le geste" do
    it "ventile la ligne sur un séjour soldé, que la file n'aurait pas proposé" do
      stay.update_column(:payment_status, "paid")
      stub_quote(lodging: 130_000)

      post ventilate_finance_cash_entry_path(entry), params: { stay_id: stay.id }

      expect(response).to redirect_to(finance_cash_entry_path(entry))
      expect(entry.cash_allocations.reload.map(&:document)).to all(eq(stay))
      expect(entry.reload).to be_fully_allocated
      expect(entry).to be_posted
    end

    it "refuse en mots un envoi sans séjour" do
      post ventilate_finance_cash_entry_path(entry), params: { stay_id: "" }

      expect(response).to redirect_to(finance_cash_entry_path(entry))
      expect(flash[:alert]).to eq("Choisis d'abord un séjour.")
      expect(entry.cash_allocations.reload).to be_empty
    end
  end
end
