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

  # Michael (2026-10-30) : choisir la structure en haut de page.
  it "filtre par structure, total compris, et préremplit la nouvelle charge" do
    srl = build_legal_entity(name: "Les 4 Sources SRL", form: "srl")
    RecurringExpense.create!(legal_entity: entity, label: "Assurance Fondation", amount_cents: 10_000,
                             frequency: "monthly", first_due_on: Date.new(2026, 10, 1))
    RecurringExpense.create!(legal_entity: srl, label: "Comptable SRL", amount_cents: 5_000,
                             frequency: "monthly", first_due_on: Date.new(2026, 10, 1))

    get finance_recurring_expenses_path
    expect(response.body).to include("Assurance Fondation", "Comptable SRL", "1 800,00 €", "toutes structures")

    get finance_recurring_expenses_path(legal_entity_id: srl.id)
    page = Nokogiri::HTML(response.body)
    expect(response.body).to include("Comptable SRL", "600,00 €", "Total des charges actives de Les 4 Sources SRL")
    expect(response.body).not_to include("Assurance Fondation")
    expect(page.at_css("select#legal_entity_id option[selected]")["value"]).to eq(srl.id.to_s)

    get page.css("a").find { |a| a.text.include?("Nouvelle charge") }["href"]
    expect(Nokogiri::HTML(response.body).at_css("#recurring_expense_legal_entity_id option[selected]")["value"]).to eq(srl.id.to_s)
  end
end
