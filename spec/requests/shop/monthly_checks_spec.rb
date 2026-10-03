require "rails_helper"
require Rails.root.join("spec/support/finance_builders")

# Epic #359, phase 5 — l'écran du contrôle mensuel des carnets.
RSpec.describe "Carnets de l'épicerie — contrôle mensuel (epic #359, phase 5)", type: :request do
  include FinanceBuilders

  let(:user) { User.create!(email: "compta-controle@les4sources.be", password: "password123") }
  let(:entity) { build_legal_entity(name: "Fondation Les 4 Sources") }
  let!(:fiscal_year) { build_fiscal_year(entity) }
  let(:bank) { build_cash_account(entity, build_general_account(code: "550000", name: "Banque")) }
  let(:caisse) { build_cash_account(entity, build_general_account(code: "570000", name: "Caisse"), name: "Caisse du domaine", kind: "cash") }
  let!(:cellier) { build_general_account(code: "701002", name: "Cellier", klass: 7, nature: "revenue") }
  let!(:boulangerie) { build_general_account(code: "701003", name: "Boulangerie", klass: 7, nature: "revenue") }
  let!(:artisanat) { build_general_account(code: "701005", name: "Artisanat (dépôt-vente)", klass: 7, nature: "revenue") }
  let!(:motif) { CashMotif.create!(label: "Épicerie", direction: "in", general_account: cellier, legal_entity: entity, position: 1) }

  def html = Nokogiri::HTML(response.body)

  def received(cents, date, account: cellier)
    build_cash_entry(bank, amount_cents: cents, entry_date: date).tap do |entry|
      allocate(entry, account: account, amount_cents: cents, entity: entity)
    end
  end

  def submit(channel, totals, validate: false)
    params = { shop_monthly_check: totals }
    params[:validate] = "Valider et figer l'écart" if validate
    patch shop_monthly_check_notebook_path("2026-06", channel), params: params
  end

  it "demande une connexion" do
    get shop_monthly_check_path("2026-06")

    expect(response).to redirect_to(new_user_session_path)
  end

  context "connecté" do
    before { sign_in user }

    it "affiche un formulaire par carnet, avec ce que la banque a déjà reçu" do
      received(4_200, Date.new(2026, 6, 9))

      get shop_monthly_check_path("2026-06")

      expect(response).to have_http_status(:ok)
      expect(html.at_css("#notebook-grocery form")).to be_present
      expect(html.at_css("#notebook-bread form")).to be_present
      expect(html.at_css("#notebook-grocery").text).to include("EPICERIE", "42,00")
    end

    it "enregistre un brouillon en euros, virgule comprise" do
      submit("grocery", { sheets_total: "100,50", transfer_total: "60", cash_total: "40,5", sheet_numbers: "12, 13" })

      check = ShopMonthlyCheck.sole
      expect(response).to redirect_to(shop_monthly_check_path("2026-06"))
      expect(check).to be_draft
      expect([check.sheets_total_cents, check.transfer_total_cents, check.cash_total_cents]).to eq([10_050, 6_000, 4_050])
      expect(check.sheet_numbers).to eq("12, 13")
    end

    it "valide et fige l'écart, puis n'affiche plus de formulaire" do
      received(5_000, Date.new(2026, 6, 9), account: boulangerie)
      submit("bread", { sheets_total: "80", transfer_total: "55", cash_total: "20" }, validate: true)

      check = ShopMonthlyCheck.sole
      expect(check).to be_validated
      expect(check.gap_cents).to eq(1_000)
      expect(check.validated_by).to eq(user)

      received(1_000, Date.new(2026, 6, 25), account: boulangerie)
      get shop_monthly_check_path("2026-06")

      expect(html.at_css("#notebook-bread form")).to be_nil
      expect(html.at_css("#notebook-bread").text).to include("+10,00")
    end

    it "refuse de réécrire un contrôle validé" do
      submit("bread", { sheets_total: "80", cash_total: "20" }, validate: true)
      submit("bread", { sheets_total: "1", cash_total: "1" })

      expect(flash[:alert]).to include("déjà validé")
      expect(ShopMonthlyCheck.sole.sheets_total_cents).to eq(8_000)
    end

    it "ventile la caisse épicerie du mois une fois les deux carnets validés" do
      entry = Finance::RecordCashLine.new(cash_account: caisse, motif: motif, entry_date: Date.new(2026, 6, 28),
                                          label: "Caisse épicerie", amount_cents: 4_000).run!
      submit("grocery", { sheets_total: "30", cash_total: "30" }, validate: true)

      get shop_monthly_check_path("2026-06")
      expect(response.body).to include("Valide d&#39;abord le contrôle Boulangerie")

      submit("bread", { sheets_total: "10", cash_total: "10" }, validate: true)
      get shop_monthly_check_path("2026-06")
      expect(response.body).to include("Ventiler 1 ligne(s)")

      post shop_monthly_check_ventilation_path("2026-06")

      expect(response).to redirect_to(shop_monthly_check_path("2026-06"))
      expect(entry.reload.cash_allocations.map { |a| [a.general_account, a.amount_cents] })
        .to contain_exactly([cellier, 3_000], [boulangerie, 1_000])
      expect(entry).to be_posted
    end

    it "liste l'historique et cumule les écarts des mois validés" do
      ShopMonthlyCheck.create!(channel: "grocery", period_month: Date.new(2026, 5, 1), status: "validated",
                               validated_at: Time.current, bank_received_cents: 0, gap_cents: 1_200)
      ShopMonthlyCheck.create!(channel: "grocery", period_month: Date.new(2026, 4, 1), status: "validated",
                               validated_at: Time.current, bank_received_cents: 0, gap_cents: -200)
      ShopMonthlyCheck.create!(channel: "bread", period_month: Date.new(2026, 5, 1), gap_cents: 9_999)

      get shop_monthly_checks_path

      expect(response).to have_http_status(:ok)
      expect(html.at_css("tfoot").text).to include("+10,00", "juste")
      expect(response.body).to include("Brouillon")
    end

    it "renvoie un mois illisible vers l'historique" do
      get "/shop/monthly_checks/2026-13"

      expect(response).to redirect_to(shop_monthly_checks_path)
    end
  end
end
