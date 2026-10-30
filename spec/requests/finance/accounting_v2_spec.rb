require "rails_helper"
require Rails.root.join("spec/support/finance_builders")

# Comptabilité, nouvelle interface : la page du collectif des administrateurs
# (Michael, 2026-10-30). Les structures côte à côte, trois horizons, puis ce
# qu'il faut trancher ensemble ; `?entity=` zoome sur une seule. L'ancienne
# interface est inchangée.
RSpec.describe "Comptabilité — nouvelle interface", type: :request do
  include FinanceBuilders
  include ActiveSupport::Testing::TimeHelpers

  let(:user) { User.create!(email: "compta-v2@les4sources.be", password: "password123", new_interface: true) }
  let(:fondation) { build_legal_entity(name: "Fondation Les 4 Sources") }
  let!(:bank) { build_general_account(code: "550000", name: "Banque") }

  around { |example| travel_to(Time.zone.local(2026, 10, 30, 10)) { example.run } }
  before { sign_in user }

  def page = Nokogiri::HTML(response.body)

  def anchor!(cash_account, cents, on: Date.current - 1)
    import = CodaImport.create!(filename: "#{cash_account.name}.cod", sha256: SecureRandom.hex(32), content: "x")
    CodaStatement.create!(coda_import: import, cash_account: cash_account, sequence_number: "1", period_year: on.year,
                          old_balance_cents: 0, new_balance_cents: cents, new_balance_date: on)
  end

  it "montre chaque structure côte à côte, sur trois horizons, et ce qu'il faut trancher" do
    anchor!(build_cash_account(fondation, bank, name: "Triodos"), 1_000_000)
    srl = build_legal_entity(name: "Domaine d'Ahinvaux SRL", form: "srl")
    build_legal_entity(name: "Écolieu", form: "simple_company")
    anchor!(build_cash_account(srl, bank, name: "Beobank"), 210_000)
    pret = build_general_account(code: "174006", name: "Prêt CT Muriel", klass: 1, nature: "liability")
    ventes = build_general_account(code: "700000", name: "Ventes", klass: 7, nature: "revenue")
    achats = build_general_account(code: "610000", name: "Services", klass: 6, nature: "expense")
    build_fiscal_year(fondation)
    post_simple_entry(entity: fondation, debit_account: bank, credit_account: pret, amount_cents: 200_000)
    post_simple_entry(entity: fondation, debit_account: bank, credit_account: ventes, amount_cents: 500_000)
    post_simple_entry(entity: fondation, debit_account: achats, credit_account: bank, amount_cents: 700_000)

    get finance_accounting_path

    expect(response).to have_http_status(:ok)
    expect(page.at_css("[data-overview]")["data-overview"]).to eq("all")
    expect(page.css(".ui-seg .ui-seg-i").map(&:text)).to eq(["Toutes", "Fondation", "SRL", "Société simple"])

    today = page.css("[data-overview-section='today'] [data-entity-today]")
    expect(today.size).to eq(3)
    foundation = page.at_css("[data-entity-today='#{fondation.id}']")
    expect(foundation["data-status"]).to eq("oui")
    expect(foundation.at_css("[data-fig='balance'] b").text).to eq("10 000 €")
    expect(foundation.at_css("[data-fig='result'] dt").text).to eq("Résultat depuis le 1er janvier")
    expect(foundation.at_css("[data-fig='result'] b").text).to eq("−2 000 €")
    expect(foundation.at_css("[data-fig='owed'] b").text).to eq("2 000 €")
    # Sans compte suivi ni exercice, la carte le dit au lieu d'inventer.
    ecolieu = today.last
    expect(ecolieu["data-status"]).to eq("inconnu")
    expect(ecolieu.text).to include("ne suit encore aucun compte bancaire", "le comptable les tient")

    expect(page.css("[data-overview-section='soon'] [data-entity-soon]").size).to eq(3)
    expect(page.css("[data-overview-section='soon'] [data-balance-lowest]")).to be_present
    later = page.at_css("[data-entity-later='#{fondation.id}']")
    expect(later.at_css("[data-fig='loans'] small").text).to include("2 000 € à court terme")
    expect(later.at_css("[data-fig='next-budget']").text).to include("Budget 2027", "À préparer")

    signals = page.css("[data-overview-section='signals'] li").map { |li| li.text.squish }
    expect(signals).to include(a_string_including("a dépensé 2 000 € de plus qu'elle n'a reçu"))
    expect(signals).to include(a_string_including("doit encore 2 000 € à 1 prêteur à court terme"))
    expect(signals).to include(a_string_including("Aucun compte bancaire de Écolieu"))
    expect(signals).to include(a_string_including("Pas encore de budget 2027"))

    # Le travail des comptables reste là, replié ; l'aide de l'écran, une fois.
    expect(page.at_css("details[data-overview-work]:not([open]) [data-accounting-todo]")).to be_present
    expect(page.at_css("[data-cash-count-reminder]").text).to include("jamais comptée")
    expect(page.at_css("[data-overview-glossary]").text).to include("Ce qu’elle vaut", "Mouvement pas classé")
    expect(page.css("[data-page-guide]").size).to eq(1)
  end

  it "met les retards légaux en tête de ce qu'il faut trancher" do
    anchor!(build_cash_account(fondation, bank, name: "Triodos"), 500_000)
    tva = ComplianceObligation.create!(legal_entity: fondation, title: "Déclaration TVA", payment: false,
                                       frequency: "yearly", first_due_on: Date.current - 5)
    ComplianceDeadline.create!(compliance_obligation: tva, period_start: Date.current.beginning_of_year,
                               due_on: Date.current - 5)

    get finance_accounting_path

    first = page.at_css("[data-overview-section='signals'] li")
    expect(first["data-signal-level"]).to eq("no")
    expect(first.text.squish).to include("1 obligation légale de Fondation Les 4 Sources en retard : Déclaration TVA")
    expect(page.at_css("[data-entity-soon] .ui-adm-dl li.is-late").text).to include("Déclaration TVA")
    expect(page.at_css(".ui-adm-lead-a").text).to eq("1 point à traiter")
  end

  it "zoome sur une structure : ses chiffres, le calcul, ses échéances seulement" do
    srl = build_legal_entity(name: "Marco & Vespucci SRL", form: "srl")
    anchor!(build_cash_account(fondation, bank, name: "Triodos"), 500_000)
    anchor!(build_cash_account(srl, bank, name: "Beobank"), 210_000)
    assurance = ComplianceObligation.create!(legal_entity: fondation, title: "Assurance incendie", payment: true,
                                             frequency: "yearly", first_due_on: Date.current + 10)
    ComplianceDeadline.create!(compliance_obligation: assurance, period_start: Date.current.beginning_of_year,
                               due_on: Date.current + 10)

    get finance_accounting_path
    expect(page.at_css("[data-entity-soon='#{fondation.id}']").text).to include("Assurance incendie")

    get finance_accounting_path(entity: srl.id)

    expect(page.at_css("[data-overview]")["data-overview"]).to eq("entity")
    expect(page.at_css(".ui-over").text).to include("Marco & Vespucci SRL")
    expect(page.at_css(".ui-seg [aria-current='page']").text).to eq("SRL")
    expect(page.css("[data-entity-today]").size).to eq(1)
    expect(page.at_css("[data-fig='balance'] b").text).to eq("2 100 €")
    expect(page.at_css("details.ui-adm-calc").text).to include("Marge", "Prêts reçus à rendre")
    expect(page.at_css("[data-entity-soon]").text).to include("Rien à tenir dans les trois mois")
  end

  it "laisse l'ancienne page à l'ancienne interface" do
    user.update!(new_interface: false)

    get finance_accounting_path

    expect(page.at_css(".ui-acc")).to be_nil
    expect(response.body).to include("Gérer les exercices")
  end
end
