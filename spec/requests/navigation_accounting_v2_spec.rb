require "rails_helper"

# La barre de la Comptabilité, nouvelle interface (Michael, 2026-11-12) : les
# files en entrées directes avec leurs compteurs, les menus pour le reste, les
# réglages derrière l'engrenage. L'ancienne interface garde son ancienne barre
# (`navigation_accounting_menus_spec`).
RSpec.describe "Barre de la Comptabilité — nouvelle interface", type: :request do
  let(:user) { User.create!(email: "barre-v2@les4sources.be", password: "password123", new_interface: true) }

  before { sign_in user }

  def subnav = Nokogiri::HTML(response.body).at_css("#subnav-accounting[data-accounting-nav='v2']")

  def entree(libelle) = subnav.at_css("a[data-nav-entry=\"#{libelle}\"]")

  def bouton(id) = subnav.at_css("#subnav-accounting-#{id}-button")

  it "pose les files en entrées directes, dans l'ordre du circuit" do
    get finance_accounting_path

    expect(subnav).to be_present
    directes = subnav.css("ul.flex > li > a[data-nav-entry]").map { |a| a["data-nav-entry"] }
    expect(directes.first(6)).to eq(["À faire", "Boîte mail", "À affecter", "Achats", "À payer", "Ventes"])
    expect(entree("À faire")["aria-current"]).to eq("page")
    expect(bouton("v2-reglages")["aria-label"]).to eq("Réglages de la comptabilité")
  end

  it "compte ce qui attend dans chaque file, sans afficher de zéro" do
    entity = LegalEntity.create!(name: "Fondation", form: "foundation", vat_regime: "exempt")
    bank = GeneralAccount.create!(code: "550000", name: "Banque", klass: 5, nature: "asset")
    account = CashAccount.create!(name: "Triodos", kind: "bank", legal_entity: entity, general_account: bank)
    2.times { |i| CashEntry.create!(cash_account: account, entry_date: Date.current - i, amount_cents: -1_000, label: "Ligne #{i}") }

    get finance_accounting_path

    expect(entree("À affecter").at_css(".ui-subnav-n").text).to eq("2")
    expect(entree("Ventes").at_css(".ui-subnav-n")).to be_nil
    expect(entree("Boîte mail").at_css(".ui-subnav-n")).to be_nil
  end

  it "allume « À affecter » plutôt que le journal sur la file, et le journal ailleurs" do
    get finance_unallocated_cash_entries_path
    expect(entree("À affecter")["aria-current"]).to eq("page")
    expect(entree("Journal de trésorerie")["class"]).not_to include("bg-teal-100")

    get finance_cash_entries_path
    expect(entree("Journal de trésorerie")["class"]).to include("bg-teal-100")
    expect(bouton("v2-banque")["class"]).to include("bg-teal-100")
    expect(entree("À affecter")["aria-current"]).to be_nil
  end

  it "range les réglages derrière l'engrenage et les allume" do
    get finance_general_accounts_path

    expect(bouton("v2-reglages")["class"]).to include("bg-teal-100")
    expect(entree("Plan comptable")["class"]).to include("bg-teal-100")
  end

  it "laisse l'ancienne barre à l'ancienne interface" do
    user.update!(new_interface: false)

    get finance_accounting_path

    html = Nokogiri::HTML(response.body)
    expect(html.at_css("[data-accounting-nav='v2']")).to be_nil
    expect(html.at_css("#subnav-accounting").text).to include("Banque & caisse")
  end

  describe "le recensement des écrans" do
    SANS_ENTREE_V2 = %w[
      finance/allocation_suggestions
      finance/carrier_statement_lines
      finance/cash_allocations
      finance/stripe_fee_invoices
    ].freeze

    before { Rails.application.eager_load! }

    ProbeV2 = Class.new do
      include Rails.application.routes.url_helpers
      include AccountingNavHelper
    end

    def recenses
      nav = ProbeV2.new
      entrees = nav.accounting_nav_v2_direct + nav.accounting_nav_v2_groups.flat_map(&:last) + [nav.accounting_nav_guide]
      entrees.flat_map(&:last).map { |ecran| ecran.split("#").first }.uniq
    end

    def ecrans_de_comptabilite
      Finance.constants.map { |c| Finance.const_get(c) }
             .select { |k| k.is_a?(Class) && k < Finance::AccountingBaseController }
             .map(&:controller_path)
    end

    it "donne une entrée de barre à chaque écran de comptabilité" do
      expect(ecrans_de_comptabilite - SANS_ENTREE_V2 - recenses).to be_empty
    end

    it "ne recense aucun contrôleur qui n'existe plus" do
      expect(recenses - ecrans_de_comptabilite).to be_empty
    end

    it "explique chaque entrée en une ligne" do
      nav = ProbeV2.new
      libelles = (nav.accounting_nav_v2_direct + nav.accounting_nav_v2_groups.flat_map(&:last)).map(&:first)
      expect(libelles.reject { |libelle| nav.accounting_nav_hint(libelle) }).to be_empty
    end
  end
end
