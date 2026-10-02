require "rails_helper"
require Rails.root.join("spec/support/finance_builders")

# Epic #359, phase 4 — un virement à mot-clé se range tout seul (proposition),
# et l'humain qui l'affecte au compte artisanat dit à quel artisan il revient.
RSpec.describe "Carnets de l'épicerie — banque (epic #359, phase 4)", type: :request do
  include FinanceBuilders

  let(:user) { User.create!(email: "compta-carnets@les4sources.be", password: "password123") }
  let(:entity) { build_legal_entity(name: "Fondation Les 4 Sources") }
  let!(:fiscal_year) { build_fiscal_year(entity) }
  let(:bank) { build_cash_account(entity, build_general_account(code: "550000", name: "Banque")) }
  let!(:artisanat) { build_general_account(code: "701005", name: "Artisanat (dépôt-vente)", klass: 7, nature: "revenue") }
  let!(:cellier) { build_general_account(code: "701002", name: "Cellier", klass: 7, nature: "revenue") }
  let!(:emilie) { Consignor.create!(name: "Émilie Dupont", settlement_mode: "invoice") }
  let!(:bruno) { Consignor.create!(name: "Bruno", settlement_mode: "invoice") }
  let!(:entry) do
    build_cash_entry(bank, amount_cents: 1_800, entry_date: Date.new(2026, 6, 10), label: "Virement")
      .tap { |e| e.update!(communication: "ARTISANAT EMILIE", counterparty_name: "CLIENT ANONYME") }
  end

  def html = Nokogiri::HTML(response.body)

  before { sign_in user }

  describe "la file « À affecter »" do
    before { Shop::SeedAllocationRules.new.run }

    it "propose l'artisanat et demande l'artisan, pré-rempli par le mot-clé" do
      get finance_unallocated_cash_entries_path

      expect(response.body).to include("Règle « Artisanat — Émilie (ARTISANAT EMILIE) »")
      select = html.at_css("select#consignor_allocation_suggestion_#{entry.allocation_suggestions.first.id}")
      expect(select).to be_present
      expect(select.at_css("option[selected]")["value"]).to eq(emilie.id.to_s)
    end

    it "accepter la suggestion rattache l'artisan choisi" do
      get finance_unallocated_cash_entries_path
      suggestion = entry.allocation_suggestions.pending.first

      patch finance_allocation_suggestion_path(suggestion, decision: "accept"), params: { consignor_id: bruno.id }

      expect(entry.reload.cash_allocations.first.general_account).to eq(artisanat)
      expect(entry.consignor).to eq(bruno)
    end
  end

  describe "l'affectation à la main" do
    it "pose l'artisan quand le compte est l'artisanat" do
      post finance_cash_entry_allocations_path(entry),
           params: { cash_allocation: { general_account_id: artisanat.id, legal_entity_id: entity.id, amount: "18,00" },
                     consignor_id: emilie.id }

      expect(entry.reload.consignor).to eq(emilie)
      expect(entry.status).to eq("allocated")
    end

    it "ignore l'artisan vers un autre compte" do
      post finance_cash_entry_allocations_path(entry),
           params: { cash_allocation: { general_account_id: cellier.id, legal_entity_id: entity.id, amount: "18,00" },
                     consignor_id: emilie.id }

      expect(entry.reload.cash_allocations.count).to eq(1)
      expect(entry.consignor).to be_nil
    end

    it "retirer l'affectation artisanat détache l'artisan" do
      post finance_cash_entry_allocations_path(entry),
           params: { cash_allocation: { general_account_id: artisanat.id, legal_entity_id: entity.id, amount: "10,00" },
                     consignor_id: emilie.id }
      allocation = entry.reload.cash_allocations.first

      delete finance_cash_entry_allocation_path(entry, allocation)

      expect(entry.reload.consignor).to be_nil
    end

    it "la fiche de la ligne propose le champ artisan, masqué tant que le compte n'est pas l'artisanat" do
      get finance_cash_entry_path(entry)

      form = html.at_css("form[data-controller='consignor-allocation']")
      expect(form["data-consignor-allocation-craft-account-id-value"]).to eq(artisanat.id.to_s)
      field = form.at_css("[data-consignor-allocation-target='field']")
      expect(field["class"]).to include("hidden")
      expect(field.at_css("option[selected]")["value"]).to eq(emilie.id.to_s)
    end
  end

  describe "le relevé de l'artisan" do
    it "affiche déclaré, reçu en banque, espèces déclarées et l'écart" do
      report = emilie.consignment_reports.create!(period_month: Date.new(2026, 6, 1), status: "declared")
      report.consignment_report_lines.create!(label: "Savon", quantity: 5, unit_price_cents: 500, payment_method: "qr")
      report.consignment_report_lines.create!(label: "Bougie", quantity: 1, unit_price_cents: 900, payment_method: "cash")
      entry.update!(consignor: emilie)

      get finance_consignment_report_path(report)

      section = html.css("section").find { |s| s.text.include?("Déclaré face à la banque") }
      expect(section).to be_present
      rows = section.css("dl > div").to_h { |row| [row.at_css("dt").text.squish, row.at_css("dd").text.squish] }
      expect(rows).to include("Déclaré" => "34 €", "Reçu en banque" => "18 €",
                              "Espèces déclarées" => "9 €", "Écart" => "7 €")
      expect(section.text).to include("ARTISANAT EMILIE")
      expect(section.text).not_to include("CLIENT ANONYME")
    end
  end

  describe "les réglages des carnets" do
    it "enregistre la correspondance carnet → compte de produit" do
      autre = build_general_account(code: "701009", name: "Pains spéciaux", klass: 7, nature: "revenue")

      patch shop_settings_path, params: { shop_setting: { bread_account_id: autre.id } }

      expect(ShopSetting.current.revenue_account(:bread)).to eq(autre)
      get shop_settings_path
      expect(response.body).to include("Comptes de produit des carnets", "Utilisé : 701009 Pains spéciaux",
                                       "Utilisé : 701005 Artisanat")
    end
  end

  describe "un artisan ouvert à l'espace" do
    it "reçoit sa règle ARTISANAT <PRÉNOM> à la création" do
      post consignors_path, params: { consignor: { name: "Chloé Martin", email: "chloe@example.com",
                                                   settlement_mode: "invoice", commission_percent: 20,
                                                   active: "1", portal_enabled: "1" } }

      rule = AllocationRule.find_by(communication_contains: "ARTISANAT CHLOE")
      expect(rule.general_account).to eq(artisanat)
      expect(rule.direction).to eq("incoming")
    end

    it "pas de règle sans accès à l'espace" do
      expect {
        post consignors_path, params: { consignor: { name: "Chloé Martin", settlement_mode: "invoice",
                                                     commission_percent: 20, active: "1" } }
      }.not_to(change { AllocationRule.count })
    end
  end
end
