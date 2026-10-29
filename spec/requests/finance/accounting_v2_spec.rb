require "rails_helper"
require Rails.root.join("spec/support/finance_builders")

# Comptabilité, Vue d'ensemble, nouvelle interface (redesign, Michael
# 2026-10-29) : la réponse en une phrase, les chiffres de l'entité choisie,
# « À faire » dans l'ordre. L'ancienne interface est inchangée.
RSpec.describe "Comptabilité — nouvelle interface", type: :request do
  include FinanceBuilders

  let(:user) { User.create!(email: "compta-v2@les4sources.be", password: "password123", new_interface: true) }
  let(:fondation) { build_legal_entity(name: "Fondation Les 4 Sources") }
  let!(:bank) { build_general_account(code: "550000", name: "Banque") }

  before { sign_in user }

  def page = Nokogiri::HTML(response.body)

  def anchor!(cash_account, cents, on: Date.current - 1)
    import = CodaImport.create!(filename: "#{cash_account.name}.cod", sha256: SecureRandom.hex(32), content: "x")
    CodaStatement.create!(coda_import: import, cash_account: cash_account, sequence_number: "1", period_year: on.year,
                          old_balance_cents: 0, new_balance_cents: cents, new_balance_date: on)
  end

  it "répond en une phrase, montre les chiffres et dit par où commencer" do
    anchor!(build_cash_account(fondation, bank, name: "Triodos"), 1_000_000)
    pret = build_general_account(code: "174006", name: "Prêt CT Muriel", klass: 1, nature: "liability")
    build_fiscal_year(fondation)
    post_simple_entry(entity: fondation, debit_account: bank, credit_account: pret, amount_cents: 200_000)

    get finance_accounting_path

    expect(response).to have_http_status(:ok)
    hero = page.at_css(".ui-acc-hero")
    expect(hero["data-spending-verdict"]).to eq("oui")
    expect(hero.at_css(".ui-acc-hero-phrase").text.squish).to start_with("Oui, jusqu’à")
    expect(hero.at_css("mark.ui-hl").text).to eq("8 000 €")
    expect(hero.at_css(".ui-acc-hero-n b").text).to eq("10 000 €")
    # Le calcul et ce que le verdict ne sait pas restent à un clic.
    expect(hero.at_css("details.ui-acc-calc").text).to include("Marge", "Prêts reçus à rendre")

    stats = page.css(".ui-acc-stat .ui-acc-stat-l").map { |label| label.text.squish }
    expect(stats).to eq(["À encaisser · 90 jours", "À payer · 90 jours", "Point bas projeté", "Caisse du bar"])
    expect(page.at_css("[data-cash-count-reminder]").text).to include("jamais comptée")

    todo = page.at_css(".ui-acc-todo")
    expect(todo.css(".ui-acc-todo-bar span").size).to eq(todo.css(".ui-acc-todo-l li").size)
    expect(todo.at_css("li.is-now").text).to include("Commencer")

    expect(page.at_css(".ui-acc-owed").text).to include("Prêt de Prêt CT Muriel", "2 000 €")
    expect(page.at_css("[data-balance-lowest]")).to be_present
    # L'aide de l'écran passe sous l'en-tête, une seule fois.
    expect(page.css("[data-page-guide]").size).to eq(1)
  end

  it "lit l'entité choisie, ses échéances seulement" do
    srl = build_legal_entity(name: "Marco & Vespucci SRL", form: "srl")
    anchor!(build_cash_account(fondation, bank, name: "Triodos"), 500_000)
    anchor!(build_cash_account(srl, bank, name: "Beobank"), 210_000)
    assurance = ComplianceObligation.create!(legal_entity: fondation, title: "Assurance incendie", payment: true,
                                             frequency: "yearly", first_due_on: Date.current + 10)
    ComplianceDeadline.create!(compliance_obligation: assurance, period_start: Date.current.beginning_of_year,
                               due_on: Date.current + 10)

    get finance_accounting_path
    expect(page.at_css(".ui-acc-deadlines").text).to include("Assurance incendie")

    get finance_accounting_path(entity: srl.id)

    expect(page.at_css(".ui-over").text).to include("Marco & Vespucci SRL")
    expect(page.at_css(".ui-seg [aria-current='page']").text).to eq("SRL")
    expect(page.at_css(".ui-acc-hero-n b").text).to eq("2 100 €")
    expect(page.at_css(".ui-acc-deadlines").text).to include("Rien à tenir dans les 30 jours")
  end

  it "laisse l'ancienne page à l'ancienne interface" do
    user.update!(new_interface: false)

    get finance_accounting_path

    expect(page.at_css(".ui-acc")).to be_nil
    expect(response.body).to include("Entités juridiques")
  end
end
