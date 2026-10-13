require "rails_helper"
require Rails.root.join("spec/support/finance_builders")
require Rails.root.join("spec/support/revenue_share_builders")

# Comptabilité > Reversements dans le connecteur (Michael, 2026-10-13) : les
# relevés des porteurs, le dépôt-vente des artisans et les partages de
# revenus. Aperçu d'abord, accord ensuite ; émettre un relevé écrit à la
# personne, et l'aperçu le dit.
RSpec.describe Mcp::Server, "finances : reversements" do
  include FinanceBuilders
  include RevenueShareBuilders

  let!(:entity) { build_legal_entity(name: "Fondation Les 4 Sources") }
  let!(:fiscal_year) { build_fiscal_year(entity, year: Date.current.year) }
  let!(:fournisseurs) { build_general_account(code: "440000", name: "Fournisseurs", klass: 4, nature: "liability") }

  let(:user) { User.create!(email: "chloe@example.com", password: "secret123456") }
  let(:server) { described_class.new(user: user) }

  def outil(name, arguments)
    server.handle({ "jsonrpc" => "2.0", "id" => 1, "method" => "tools/call",
                    "params" => { "name" => name, "arguments" => arguments } })[:result]
  end

  def texte(result) = result[:content].first[:text]

  def confirme(name, arguments)
    apercu = outil(name, arguments)
    expect(apercu[:isError]).to be(false), texte(apercu)
    resultat = outil(name, arguments.merge("confirmation" => texte(apercu)[/confirmation: "([^"]+)"/, 1]))
    expect(resultat[:isError]).to be(false), texte(resultat)
    texte(resultat)
  end

  describe "les relevés des porteurs" do
    let!(:remunerations) { build_general_account(code: "616000", name: "Rémunérations d'intervenants", klass: 6, nature: "expense") }
    let!(:carrier) { Human.create!(name: "Sébastien", email: "seb@les4sources.be") }
    let!(:experience) { Experience.create!(name: "Initiation vannerie", human: carrier, team: Team.create!(name: "Transmission"), duration_hours: 2) }
    let(:stay) do
      customer = Customer.create!(email: "lea@example.com", first_name: "Léa", customer_type: "individual")
      Stay.create!(customer: customer, status: "confirmed", arrival_date: Date.current - 40, departure_date: Date.current - 38)
    end

    def held_booking(on:)
      slot = ExperienceAvailability.create!(experience: experience, available_on: on, starts_at: "10:00", duration_minutes: 120)
      booking = ExperienceBooking.create!(experience_availability: slot, stay: stay, participants: 2, status: "confirmed")
      booking.update_columns(outcome: "held", outcome_recorded_at: Time.current)
      booking
    end

    it "génère un brouillon, prévient avant d'émettre, émet et envoie" do
      held_booking(on: Date.current - 30)
      held_booking(on: Date.current - 20)
      expect(texte(outil("releves_porteurs", {}))).to include("Sébastien", "à relever : 2 prestation(s)")

      arguments = { "geste" => "generer", "porteur" => "Sébastien", "du" => (Date.current - 60).to_s, "au" => Date.current.to_s }
      expect(texte(outil("releve_porteur", arguments))).to include("Générer un brouillon pour Sébastien", "Initiation vannerie")
      expect(CarrierStatement.count).to eq(0)

      expect(confirme("releve_porteur", arguments)).to include("Brouillon généré")
      releve = CarrierStatement.last
      expect(releve).to be_draft
      expect(releve.carrier_statement_lines.count).to eq(2)

      ActionMailer::Base.deliveries.clear
      emettre = { "geste" => "emettre", "releve" => releve.reference }
      expect(texte(outil("releve_porteur", emettre))).to include("ÉCRIT AU PORTEUR", "seb@les4sources.be")
      expect(ActionMailer::Base.deliveries).to be_empty

      expect(confirme("releve_porteur", emettre)).to include("Relevé émis", "envoyé à seb@les4sources.be")
      expect(releve.reload).to be_issued
      expect(releve.posted_at).to be_present
      expect(ActionMailer::Base.deliveries.last.to).to eq(["seb@les4sources.be"])

      refus = outil("releve_porteur", { "geste" => "supprimer", "releve" => releve.id })
      expect(texte(refus)).to include("ne se supprime pas")
    end

    it "supprime un brouillon et libère ses prestations" do
      held_booking(on: Date.current - 30)
      releve = CarrierStatements::Generate.new(human: carrier, period_from: Date.current - 60, period_to: Date.current).run!

      confirme("releve_porteur", { "geste" => "supprimer", "releve" => releve.id })
      expect(CarrierStatement.find_by(id: releve.id)).to be_nil
      expect(CarrierStatements::Selection.new(human: carrier).bookings.size).to eq(1)
    end
  end

  describe "le dépôt-vente" do
    let!(:marchandises) { build_general_account(code: "600000", name: "Achats de marchandises", klass: 6, nature: "expense") }
    let!(:eline) do
      Consignor.create!(name: "Eline", email: "eline@example.com", settlement_mode: "transfer",
                        commission_percent: 20, iban: "BE68539007547034")
    end
    let!(:releve) do
      ConsignmentReport.create!(consignor: eline, period_month: Date.new(Date.current.year, 8, 1), status: "declared",
                                declared_at: Time.current).tap do |r|
        r.consignment_report_lines.create!(label: "Bougie", quantity: 4, unit_price_cents: 1_200, position: 0)
        r.consignment_report_lines.create!(label: "Savon", quantity: 2, unit_price_cents: 800, position: 1)
      end
    end

    it "corrige une ligne, vérifie puis règle par virement" do
      mois = "#{Date.current.year}-08"
      expect(texte(outil("depot_vente", { "mois" => mois }))).to include("Eline", "déclaré", "ventes 64,00 €")
      bougie = releve.consignment_report_lines.find_by(label: "Bougie")
      expect(texte(outil("depot_vente", { "artisan" => "Eline", "mois" => mois }))).to include("ligne ##{bougie.id} · Bougie")

      corriger = { "geste" => "corriger", "releve" => releve.reference,
                   "lignes" => [{ "ligne" => bougie.id, "quantite" => 3 }, { "libelle" => "Carte postale", "quantite" => 5, "prix_unitaire" => "2" }] }
      expect(texte(outil("releve_depot_vente", corriger))).to include("Carte postale", "ventes 62,00 €")
      expect(bougie.reload.quantity).to eq(4)
      confirme("releve_depot_vente", corriger)
      expect(releve.reload.live_gross_cents).to eq(3 * 1_200 + 2 * 800 + 5 * 200)

      verifier = { "geste" => "verifier", "releve" => releve.id }
      expect(texte(outil("releve_depot_vente", verifier))).to include("net dû à Eline 49,60 €")
      expect(releve.reload).to be_declared
      confirme("releve_depot_vente", verifier)
      expect(releve.reload).to have_attributes(status: "verified", net_cents: 4_960, verified_by: user)

      refus = outil("releve_depot_vente", { "geste" => "corriger", "releve" => releve.id, "notes" => "x" })
      expect(texte(refus)).to include("ne se corrigent plus")

      confirme("releve_depot_vente", { "geste" => "regler", "releve" => releve.id })
      expect(releve.reload).to be_posted
      expect(texte(outil("depot_vente", { "annee" => Date.current.year }))).to include("Eline · 1 relevé(s)")
    end

    it "lie la facture d'un artisan qui facture" do
      eline.update!(settlement_mode: "invoice")
      releve.update!(status: "verified", net_cents: 5_120)
      tiers = ThirdParty.create!(name: "Eline Artisanat", kind: "supplier")
      facture = PurchaseInvoice.create!(third_party: tiers, legal_entity: entity, number: "E-12", total_cents: 5_120,
                                        issued_on: Date.current, status: "to_process")

      confirme("releve_depot_vente", { "geste" => "lier_facture", "releve" => releve.id, "facture" => facture.id })
      expect(releve.reload.purchase_invoice).to eq(facture)
      confirme("releve_depot_vente", { "geste" => "detacher_facture", "releve" => releve.id })
      expect(releve.reload.purchase_invoice).to be_nil
    end
  end

  describe "les partages de revenus" do
    let(:lodging) { build_tiny_house }
    let!(:reversements) do
      build_general_account(code: GeneralAccount::REVENUE_SHARE_CODE, name: "Reversements", klass: 6, nature: "expense")
    end

    it "crée l'accord, génère, émet puis marque payé" do
      lodging
      confirme("accord_partage", { "hebergement" => "Tiny", "beneficiaire" => "Famille Dubois", "email" => "dubois@example.com",
                                   "debut" => "#{Date.current.year}-01-01" })
      accord = RevenueShareAgreement.last
      expect(accord).to have_attributes(share_percent: 50, period: "quarterly", beneficiary_email: "dubois@example.com")
      build_tiny_booking(lodging, from: Date.new(Date.current.year, 1, 10), price_cents: 50_000)

      generer = { "geste" => "generer", "accord" => "Tiny", "periode" => "#{Date.current.year}-01-01" }
      expect(texte(outil("releve_partage", generer))).to include("T1 #{Date.current.year}", "part 250,00 €")
      confirme("releve_partage", generer)
      releve = RevenueShareStatement.last
      expect(releve).to be_draft

      ActionMailer::Base.deliveries.clear
      emettre = { "geste" => "emettre", "releve" => releve.reference }
      expect(texte(outil("releve_partage", emettre))).to include("ÉCRIT AU BÉNÉFICIAIRE", "dubois@example.com")
      confirme("releve_partage", emettre)
      expect(releve.reload).to be_issued
      expect(ActionMailer::Base.deliveries.last.to).to eq(["dubois@example.com"])

      confirme("releve_partage", { "geste" => "marquer_paye", "releve" => releve.id, "date" => Date.current.to_s })
      expect(releve.reload).to have_attributes(status: "paid", paid_on: Date.current)
      expect(texte(outil("partages_revenus", { "accord" => accord.id }))).to include("payé")

      confirme("accord_partage", { "accord" => accord.id, "actif" => false })
      expect(accord.reload).not_to be_active
    end
  end
end
