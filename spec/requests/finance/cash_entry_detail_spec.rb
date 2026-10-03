require "rails_helper"
require Rails.root.join("spec/support/finance_builders")

# Epic #288, phase 5 — le détail d'une ligne s'ouvre en modale depuis la file
# « À affecter », sans la quitter. La page pleine reste l'URL qu'on partage.
RSpec.describe "Comptabilité — détail d'une ligne en modale", type: :request do
  include Devise::Test::IntegrationHelpers
  include FinanceBuilders

  let(:user) { User.create!(email: "compta@les4sources.be", password: "password123") }
  let(:entity) { build_legal_entity }
  let!(:fiscal_year) { build_fiscal_year(entity) }
  let!(:revenue) { build_general_account(code: "700000", name: "Hébergement", klass: 7, nature: "revenue") }
  let!(:bank) { build_cash_account(entity, build_general_account(code: "550000", name: "Banque")) }
  let!(:team) { Team.create!(name: "Pôle Accueil", kind: "economic") }
  let!(:entry) do
    build_cash_entry(bank, amount_cents: 30_000, label: "Virement séjour").tap do |e|
      e.update!(communication: "Séjour Dupont acompte\nsolde à l'arrivée", counterparty_name: "Hélène Dupont",
                counterparty_iban: "BE68539007547034", value_date: Date.new(2026, 6, 16),
                transaction_code: "00150000", statement_ref: "2026/117")
    end
  end

  before { sign_in user }

  def get_detail(e = entry)
    get detail_finance_cash_entry_path(e), headers: { "Turbo-Frame" => "modal" }
  end

  it "montre les champs que la file tait : date de valeur, code opération, IBAN, relevé" do
    get_detail

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(%(<turbo-frame id="modal">))
    expect(response.body).to include("16/06/2026")
    expect(response.body).to include("00150000")
    expect(response.body).to include("BE68539007547034")
    expect(response.body).to include("2026/117")
    expect(response.body).to include("Banque Triodos")
    expect(response.body).to include("Hélène Dupont")
    expect(response.body).to include("solde à l&#39;arrivée")
  end

  it "liste les affectations posées et le reste, sur une ligne à moitié affectée" do
    allocate(entry, account: revenue, amount_cents: 12_000, entity: entity, team: team)

    get_detail

    expect(response.body).to include("700000")
    expect(response.body).to include("Pôle Accueil")
    expect(response.body).to include(entity.name)
    expect(response.body).to include("120,00 €")
    expect(response.body).to match(/Reste à affecter :.*180,00 €/m)
  end

  it "ne propose aucun geste : elle montre, elle ne classe pas" do
    get_detail

    expect(response.body).not_to include("<form")
    expect(response.body).not_to include("Retirer")
  end

  it "porte un lien vers la page pleine de la ligne" do
    get_detail

    expect(response.body).to include(%(href="#{finance_cash_entry_path(entry)}"))
    expect(response.body).to include("Ouvrir la page de la ligne")
  end

  it "laisse la page pleine répondre comme avant" do
    get finance_cash_entry_path(entry)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Affecter le reste")
    expect(response.body).to include("Exclure cette ligne")
  end

  it "ouvre le détail depuis la file, dans le cadre de la modale" do
    get finance_unallocated_cash_entries_path

    expect(response.body).to include(%(href="#{detail_finance_cash_entry_path(entry)}"))
    expect(response.body).to include(%(data-turbo-frame="modal"))
  end
end
