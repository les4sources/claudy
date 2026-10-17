require "rails_helper"
require Rails.root.join("spec/support/finance_builders")

# Le guide de la comptabilité et l'aide de chaque écran (Michael, 2026-10-17) :
# ce qu'il faut à une personne qui démarre. Le risque, c'est l'oubli : un
# nouvel écran sans aide, un mot cité qui n'est pas au lexique. D'où les
# recensements ci-dessous.
RSpec.describe "Comptabilité > Guide", type: :request do
  include FinanceBuilders

  let(:user) { User.create!(email: "guide@les4sources.be", password: "password123") }

  before { sign_in user }

  def page_guide = Nokogiri::HTML(response.body).at_css("[data-page-guide]")

  describe "la page du guide" do
    it "explique le circuit, la routine et le lexique" do
      get finance_guide_path

      corps = CGI.unescapeHTML(response.body)
      expect(response).to have_http_status(:ok)
      expect(corps).to include("Comment l'argent circule", "Ta routine", "Lexique")
      expect(corps).to include("Contre-passer", "Rapprocher", "À-nouveau")
    end

    it "mène chaque geste de la routine vers son écran" do
      get finance_guide_path

      liens = Nokogiri::HTML(response.body).css("main a, body a").map { |a| a["href"] }
      expect(liens).to include(finance_unallocated_cash_entries_path, finance_monthly_close_path, finance_payables_path)
    end

    it "donne une ancre à chaque mot du lexique" do
      get finance_guide_path

      html = Nokogiri::HTML(response.body)
      expect(Finance::Guide::TERMS.keys.reject { |key| html.at_css("##{key}") }).to be_empty
    end
  end

  describe "l'aide sous le titre" do
    it "dit à quoi sert l'écran, comment faire et les mots à connaître" do
      get finance_ledger_path

      expect(page_guide).to be_present
      expect(page_guide.text).to include("À quoi sert cette page ?", "Comment faire", "Grand livre")
    end

    # La file « À affecter » n'est pas le journal : elle a sa propre aide.
    it "préfère l'aide d'une action à celle de son écran" do
      get finance_unallocated_cash_entries_path

      expect(page_guide.text).to include("La file des mouvements qu'il reste à expliquer")
    end

    # La section Comptes est celle des habitants, pas de la comptabilité.
    it "ne s'affiche pas hors de la Comptabilité" do
      get finance_accounts_path

      expect(page_guide).to be_nil
    end
  end

  describe "le recensement" do
    # Les écrans qu'on n'ouvre jamais seuls : ils répondent à un formulaire
    # posé ailleurs et ne rendent pas de page.
    SANS_PAGE = %w[
      finance/allocation_suggestions
      finance/cash_allocations
      finance/stripe_fee_invoices
    ].freeze

    before { Rails.application.eager_load! }

    def ecrans_de_comptabilite
      Finance.constants.map { |c| Finance.const_get(c) }
             .select { |k| k.is_a?(Class) && k < Finance::AccountingBaseController }
             .map(&:controller_path)
    end

    it "donne une aide à chaque écran de la Comptabilité" do
      sans_aide = (ecrans_de_comptabilite - SANS_PAGE).reject { |chemin| Finance::Guide::PAGES.key?(chemin) }

      expect(sans_aide).to be_empty
    end

    it "ne cite que des mots qui sont au lexique" do
      cites = Finance::Guide::PAGES.values.flat_map(&:terms).uniq

      expect(cites - Finance::Guide::TERMS.keys).to be_empty
    end
  end

  describe "« À faire » sur la vue d'ensemble" do
    let(:entity) { build_legal_entity }
    let(:bank) { build_general_account(code: "550000", name: "Banque") }

    it "liste les files dans l'ordre et compte ce qui attend" do
      build_fiscal_year(entity)
      compte = build_cash_account(entity, bank)
      build_cash_entry(compte)

      get finance_accounting_path

      bloc = Nokogiri::HTML(response.body).at_css("[data-accounting-todo]")
      libelles = bloc.css("li p.font-medium").map { |p| p.text.strip }
      expect(libelles.first(3)).to eq(["Classer les mails reçus", "Importer les relevés bancaires", "Affecter les mouvements"])
      affecter = bloc.css("li").find { |li| li.text.include?("Affecter les mouvements") }
      expect(affecter["data-todo-state"]).to eq("todo")
      expect(affecter.text).to include("1 ligne(s)")
    end

    it "coche une file vide" do
      get finance_accounting_path

      bloc = Nokogiri::HTML(response.body).at_css("[data-accounting-todo]")
      mails = bloc.css("li").find { |li| li.text.include?("Classer les mails reçus") }
      expect(mails["data-todo-state"]).to eq("done")
    end
  end
end
