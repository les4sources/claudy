require "rails_helper"
require Rails.root.join("spec/support/finance_builders")

# Le filtre « Structure » en pastilles (Michael, 2026-10-30) : le même partout,
# celui de l'Échéancier. Des liens qui gardent les autres filtres de l'URL.
RSpec.describe "Finances > filtre « Structure »", type: :request do
  include FinanceBuilders

  let(:user) { User.create!(email: "compta-filtre@les4sources.be", password: "password123") }
  let!(:fondation) { build_legal_entity(name: "Fondation Les 4 Sources") }
  let!(:srl) { build_legal_entity(name: "Domaine d'Ahinvaux SRL", form: "srl") }

  before { sign_in user }

  def pills
    Nokogiri::HTML(response.body).css("nav[data-entity-filter] a")
  end

  def active_pill
    Nokogiri::HTML(response.body).at_css("nav[data-entity-filter] a[aria-current='page']")
  end

  def pill(name)
    pills.find { |link| link.text == name }
  end

  it "est en pastilles sur chaque écran qui filtre par structure, sans liste déroulante" do
    [finance_payables_path, finance_recurring_expenses_path, finance_compliance_deadlines_path,
     finance_ledger_path, finance_trial_balance_path, finance_analytic_balance_path,
     finance_sales_invoices_path, finance_purchase_invoices_path, finance_expense_reports_path,
     finance_fiscal_years_path].each do |path|
      get path

      expect(response).to have_http_status(:ok), path
      expect(pills.map(&:text)).to include("Toutes", "Fondation Les 4 Sources", "Domaine d'Ahinvaux SRL"), path
      expect(active_pill.text).to eq("Toutes"), path
      expect(Nokogiri::HTML(response.body).at_css("select[name='legal_entity_id']")).to be_nil, path
    end
  end

  it "garde les autres filtres de l'URL et pose la structure dans le formulaire voisin" do
    get finance_trial_balance_path(from: "2026-01-01", to: "2026-06-30")

    href = pill("Domaine d'Ahinvaux SRL")["href"]
    expect(Rack::Utils.parse_query(URI(href).query)).to eq("from" => "2026-01-01", "to" => "2026-06-30", "legal_entity_id" => srl.id.to_s)

    get href
    expect(active_pill.text).to eq("Domaine d'Ahinvaux SRL")
    expect(Nokogiri::HTML(response.body).at_css("input[type='hidden'][name='legal_entity_id']")["value"]).to eq(srl.id.to_s)
    expect(URI(pill("Toutes")["href"]).query).to eq("from=2026-01-01&to=2026-06-30")
  end

  it "garde le paramètre propre à l'Échéancier" do
    get finance_compliance_deadlines_path(entity: srl.id)

    expect(active_pill.text).to eq("Domaine d'Ahinvaux SRL")
    expect(pill("Fondation Les 4 Sources")["href"]).to eq(finance_compliance_deadlines_path(entity: fondation.id))
    expect(pill("Toutes")["href"]).to eq(finance_compliance_deadlines_path)
  end

  it "exige une structure sur les Immobilisations et oublie l'exercice en en changeant" do
    year = build_fiscal_year(fondation, year: Date.current.year)

    get finance_fixed_assets_path(legal_entity_id: fondation.id, fiscal_year_id: year.id)

    expect(pills.map(&:text)).not_to include("Toutes")
    expect(active_pill.text).to eq("Fondation Les 4 Sources")
    expect(pill("Domaine d'Ahinvaux SRL")["href"]).to eq(finance_fixed_assets_path(legal_entity_id: srl.id))
  end

  it "exige une structure sur le Budget, par `entity_id`" do
    get finance_budget_path(entity_id: srl.id, year: Date.current.year)

    expect(pills.map(&:text)).not_to include("Toutes")
    expect(active_pill.text).to eq("Domaine d'Ahinvaux SRL")
    expect(Rack::Utils.parse_query(URI(pill("Fondation Les 4 Sources")["href"]).query))
      .to eq("entity_id" => fondation.id.to_s, "year" => Date.current.year.to_s)
  end
end
