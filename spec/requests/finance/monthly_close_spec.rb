require "rails_helper"
require Rails.root.join("spec/support/finance_builders")

RSpec.describe "Finances > Arrêté du mois", type: :request do
  include FinanceBuilders

  let(:user) { User.create!(email: "compta@les4sources.be", password: "password123") }
  let(:month) { Date.new(2026, 8, 1) }
  let(:entity) { build_legal_entity }
  let!(:fiscal_year) { build_fiscal_year(entity) }
  let(:bank_account) { build_general_account(code: "550000", name: "Banque") }
  let!(:cash_account) { build_cash_account(entity, bank_account) }

  before { sign_in user }

  it "affiche le verdict avant le détail" do
    get finance_monthly_close_path(month: "2026-08")

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("à traiter").or include("Tout est fait")
    expect(response.body).to include("Les mouvements bancaires du mois sont entrés")
  end

  # Le bouton ne se grise pas « par prudence » : il refuse, et il dit pourquoi.
  it "refuse d'arrêter un mois qui a encore des points ouverts, en les nommant" do
    expect {
      post finance_close_monthly_close_path(month: "2026-08")
    }.not_to change { MonthClosing.count }

    follow_redirect!
    expect(response.body).to include("Il reste").and include("mouvements bancaires")
  end

  it "arrête le mois quand plus rien ne bloque" do
    build_cash_entry(cash_account, entry_date: Date.new(2026, 8, 12), amount_cents: 50_000).tap do |entry|
      allocate(entry, account: build_general_account(code: "700000", name: "Locations", klass: 7, nature: "revenue"),
               amount_cents: 50_000, entity: entity)
      Accounting::PostCashEntry.new(cash_entry: entry).run!
    end

    expect {
      post finance_close_monthly_close_path(month: "2026-08"), params: { notes: "Rien à signaler" }
    }.to change { MonthClosing.count }.by(1)

    expect(MonthClosing.last.closed_by).to eq(user.email)
    follow_redirect!
    expect(response.body).to include("Mois arrêté")
  end

  it "rouvre un mois arrêté" do
    MonthClosing.create!(period_month: month, closed_at: Time.current)

    expect {
      post finance_reopen_monthly_close_path(month: "2026-08")
    }.to change { MonthClosing.count }.by(-1)
  end
end
