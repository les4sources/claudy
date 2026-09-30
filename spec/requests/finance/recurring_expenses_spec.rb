require "rails_helper"
require Rails.root.join("spec/support/finance_builders")

# Comptabilité > Fournisseurs > Charges fixes (2026-09-30).
RSpec.describe "Comptabilité > Charges fixes", type: :request do
  include Devise::Test::IntegrationHelpers
  include FinanceBuilders

  let(:user) { User.create!(email: "compta-charges@les4sources.be", password: "password123") }
  let!(:entity) { build_legal_entity(name: "Fondation Les 4 Sources") }
  let!(:orange) { ThirdParty.create!(name: "Orange Belgium", kind: "supplier") }

  before { sign_in user }

  it "dit son vide" do
    get finance_recurring_expenses_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Aucune charge fixe")
  end

  it "crée une charge avec un montant saisi à la belge, puis la liste" do
    post finance_recurring_expenses_path, params: { recurring_expense: {
      label: "Abonnement internet Voo", third_party_id: orange.id, legal_entity_id: entity.id,
      amount: "67,76", frequency: "monthly", first_due_on: "2026-10-27", active: "1"
    } }

    expect(response).to redirect_to(finance_recurring_expenses_path)
    voo = RecurringExpense.last
    expect(voo.amount_cents).to eq(6_776)
    expect(voo.third_party).to eq(orange)

    get finance_recurring_expenses_path
    expect(response.body).to include("Abonnement internet Voo")
    expect(response.body).to include("813,12 €") # 12 × 67,76
  end

  it "refuse une charge sans montant et le dit" do
    post finance_recurring_expenses_path, params: { recurring_expense: {
      label: "Voo", legal_entity_id: entity.id, amount: "", frequency: "monthly", first_due_on: "2026-10-27"
    } }

    expect(response).to have_http_status(:unprocessable_entity)
    expect(RecurringExpense.count).to eq(0)
  end

  it "modifie puis supprime une charge" do
    voo = RecurringExpense.create!(legal_entity: entity, label: "Voo", amount_cents: 6_776,
                                   frequency: "monthly", first_due_on: Date.new(2026, 10, 27))

    patch finance_recurring_expense_path(voo), params: { recurring_expense: { amount: "69,90" } }
    expect(voo.reload.amount_cents).to eq(6_990)

    delete finance_recurring_expense_path(voo)
    expect(response).to redirect_to(finance_recurring_expenses_path)
    expect(RecurringExpense.count).to eq(0)
  end

  it "préremplit le formulaire depuis une facture d'achat (« Cette charge revient »)" do
    build_fiscal_year(entity)
    charges = build_general_account(code: "614000", name: "Télécom", klass: 6, nature: "expense")
    invoice = PurchaseInvoice.create!(legal_entity: entity, third_party: orange, number: "F-1",
                                      issued_on: Date.new(2026, 9, 1), due_on: Date.new(2026, 9, 27), total_cents: 6_776)
    invoice.purchase_invoice_lines.create!(general_account: charges, amount_cents: 6_776)

    get finance_purchase_invoice_path(invoice)
    link = Nokogiri::HTML(response.body).css("a").find { |a| a.text.include?("Cette charge revient") }
    expect(link).to be_present

    get link["href"]
    form = Nokogiri::HTML(response.body)
    expect(form.at_css("#recurring_expense_label")["value"]).to eq("Orange Belgium")
    expect(form.at_css("#recurring_expense_amount")["value"]).to eq("67,76")
    expect(form.at_css("#recurring_expense_first_due_on")["value"]).to eq("2026-10-27")
    expect(form.at_css("#recurring_expense_third_party_id option[selected]")["value"]).to eq(orange.id.to_s)
    expect(form.at_css("#recurring_expense_general_account_id option[selected]")["value"]).to eq(charges.id.to_s)
  end
end
