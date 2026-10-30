require "rails_helper"
require Rails.root.join("spec/support/finance_builders")

# Epic #240, phase 4 — la file « À payer ».
#
# L'écran du mercredi matin devant Triodos : qu'est-ce que je vire aujourd'hui,
# à qui, sur quel compte, avec quelle communication.
RSpec.describe "Comptabilité > À payer", type: :request do
  include Devise::Test::IntegrationHelpers
  include FinanceBuilders

  let(:user) { User.create!(email: "compta-payables@les4sources.be", password: "password123") }
  let!(:entity) { build_legal_entity(name: "Fondation Les 4 Sources") }
  let!(:fiscal_year) { build_fiscal_year(entity) }
  let!(:charges) { build_general_account(code: "612000", name: "Énergie", klass: 6, nature: "expense") }
  let!(:fournisseurs) { build_general_account(code: "440000", name: "Fournisseurs", klass: 4, nature: "liability") }
  let!(:antargaz) { ThirdParty.create!(name: "Antargaz", kind: "supplier", iban: "BE68539007547034") }
  let!(:sans_compte) { ThirdParty.create!(name: "Le Maraîcher", kind: "supplier") }

  before { sign_in user }

  def facture(tiers: antargaz, total: 12_000, number: "F-1", due_on: nil, payable: true)
    f = PurchaseInvoice.create!(legal_entity: entity, third_party: tiers, number: number,
                               issued_on: Date.new(2026, 6, 1), due_on: due_on, total_cents: total)
    f.purchase_invoice_lines.create!(general_account: charges, amount_cents: total)
    payable ? PurchaseInvoices::Advance.new(purchase_invoice: f).submit! : f.reload
  end

  it "dit son vide plutôt que d'afficher une liste creuse" do
    get finance_payables_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Rien à payer")
  end

  it "liste les factures « à payer », avec IBAN, communication et total" do
    facture(due_on: Date.current + 10)

    get finance_payables_path

    expect(response.body).to include("Antargaz")
    expect(response.body).to include("BE68539007547034")
    expect(response.body).to include("F-1")
    expect(response.body).to include("120 €")
    expect(response.body).to include("subnav-accounting")
  end

it "propose la communication structurée de la facture plutôt que son numéro" do
  facture.update!(payment_reference: "+++000/0024/11862+++")

  get finance_payables_path

  expect(response.body).to include('data-copy-value-value="+++000/0024/11862+++"')
  expect(response.body).not_to include('data-copy-value-value="F-1"')
end

  it "n'y fait pas figurer une facture qui n'est pas encore validée" do
    facture(number: "BROUILLON", payable: false)

    get finance_payables_path

    expect(response.body).not_to include("BROUILLON")
    expect(response.body).to include("Rien à payer")
  end

  # L'ordre de l'écran est l'ordre dans lequel on paie, pas l'ordre de saisie.
  it "trie par échéance, les sans-échéance en dernier" do
    facture(number: "TARD", due_on: Date.current + 30)
    facture(number: "TOT", due_on: Date.current + 2)
    facture(number: "JAMAIS", due_on: nil)

    get finance_payables_path
    positions = %w[TOT TARD JAMAIS].map { |n| response.body.index(n) }

    expect(positions).to eq(positions.sort)
  end

  it "met le retard en évidence, avec le nombre de jours" do
    facture(number: "RETARD", due_on: Date.current - 7)

    get finance_payables_path

    expect(response.body).to include("en retard de 7 j")
    expect(response.body).to include("En retard")
  end

  # On ne CACHE jamais un payable sans IBAN : faire disparaître une dette parce
  # qu'il manque une coordonnée est la meilleure façon de ne jamais la payer.
  it "garde dans la liste une facture dont le tiers n'a pas d'IBAN, en la marquant" do
    facture(tiers: sans_compte, number: "SANS-IBAN", due_on: Date.current + 5)

    get finance_payables_path

    expect(response.body).to include("Le Maraîcher")
    expect(response.body).to include("sans IBAN")
  end

  it "montre ce qui est déjà rapproché sur un paiement partiel" do
    f = facture(due_on: Date.current + 5)
    banque = build_cash_account(entity, build_general_account(code: "550000", name: "Banque"))
    acompte = build_cash_entry(banque, amount_cents: -5_000, label: "Acompte")
    acompte.cash_allocations.create!(general_account: fournisseurs, legal_entity: entity,
                                     third_party: antargaz, document: f, amount_cents: -5_000)

    get finance_payables_path

    expect(response.body).to include("déjà rapproché")
    expect(response.body).to include("70 €")
  end

  it "est atteignable depuis la sous-navigation Comptabilité" do
    get finance_payables_path

    expect(response.body).to include(%(href="#{finance_payables_path}"))
  end

  # Michael (2026-10-30) : « on ne comprend pas s'il s'agit de toutes les
  # structures ou d'une seule ». Le filtre « Structure » en haut de page.
  describe "filtre « Structure »" do
    let!(:srl) { build_legal_entity(name: "Les 4 Sources SRL", form: "srl") }
    let!(:srl_year) { build_fiscal_year(srl) }

    before do
      facture(number: "FONDATION-1", due_on: Date.current + 5)
      f = PurchaseInvoice.create!(legal_entity: srl, third_party: antargaz, number: "SRL-1",
                                  issued_on: Date.new(2026, 6, 1), due_on: Date.current + 3, total_cents: 5_000)
      f.purchase_invoice_lines.create!(general_account: charges, amount_cents: 5_000)
      PurchaseInvoices::Advance.new(purchase_invoice: f).submit!
    end

    it "montre toutes les structures par défaut, chaque ligne avec la sienne" do
      get finance_payables_path

      page = Nokogiri::HTML(response.body)
      expect(page.at_css("select#legal_entity_id option[selected]")).to be_nil
      expect(page.at_css("select#legal_entity_id option[value='']").text).to eq("Toutes les structures")
      expect(response.body).to include("FONDATION-1", "SRL-1", "170 €")
      expect(page.css("li span.rounded-full").map(&:text)).to include("Fondation Les 4 Sources", "Les 4 Sources SRL")
    end

    it "ne garde que la structure choisie, total compris" do
      get finance_payables_path(legal_entity_id: srl.id)

      expect(response.body).to include("SRL-1", "Seulement Les 4 Sources SRL")
      expect(response.body).not_to include("FONDATION-1")
      expect(response.body).to include("50 €")
      expect(Nokogiri::HTML(response.body).at_css("select#legal_entity_id option[selected]")["value"]).to eq(srl.id.to_s)
    end

    it "dit son vide pour la structure choisie" do
      vide = build_legal_entity(name: "SSI Ahinvaux", form: "simple_company")

      get finance_payables_path(legal_entity_id: vide.id)

      expect(response.body).to include("Rien à payer pour SSI Ahinvaux")
    end
  end

  # Un relevé de porteur n'a pas de colonne d'entité : c'est l'écriture d'achat
  # qui la porte.
  describe "Payable#payable_legal_entity" do
    it "lit la structure de l'écriture d'achat quand le document n'en a pas" do
      build_general_account(code: GeneralAccount::CONTRIBUTOR_FEE_CODE, name: "Rémunérations", klass: 6, nature: "expense")
      carrier = Human.create!(name: "Sébastien", email: "seb@les4sources.be")
      experience = Experience.create!(name: "Vannerie", human: carrier, team: Team.create!(name: "Transmission"), duration_hours: 2)
      customer = Customer.create!(email: "lea@example.com", first_name: "Léa", customer_type: "individual")
      stay = Stay.create!(customer: customer, status: "confirmed", arrival_date: Date.current - 40, departure_date: Date.current - 38)
      slot = ExperienceAvailability.create!(experience: experience, available_on: Date.current - 30, starts_at: "10:00", duration_minutes: 120)
      ExperienceBooking.create!(experience_availability: slot, stay: stay, participants: 2, status: "confirmed")
                       .update_columns(outcome: "held", outcome_recorded_at: Time.current)
      releve = CarrierStatements::Generate.new(human: carrier, period_from: Date.current - 60, period_to: Date.current).run!
      CarrierStatements::Issue.new(statement: releve).run!

      expect(releve.reload.payable_legal_entity).to eq(entity)
      expect(Finance::PayableQueue.new(legal_entity: entity).rows).to include(releve)
      expect(Finance::PayableQueue.new(legal_entity: build_legal_entity(name: "Autre", form: "srl")).rows).to be_empty
    end
  end
end
