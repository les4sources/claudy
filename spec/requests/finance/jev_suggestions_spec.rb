require "rails_helper"
require Rails.root.join("spec/support/finance_builders")
require Rails.root.join("spec/support/mail_intake_helpers")

# La proposition de Jev arrive ligne par ligne, à la volée : l'écran « À
# affecter » ne l'attend jamais, et une ligne ne se redemande pas.
RSpec.describe "Finances > Trésorerie > propositions de Jev", type: :request do
  include FinanceBuilders

  let(:user) { User.create!(email: "compta@les4sources.be", password: "password123") }
  let(:entity) { build_legal_entity }
  let!(:fiscal_year) { build_fiscal_year(entity) }
  let!(:bank_account) { build_general_account(code: "550000", name: "Banque") }
  let!(:bar) { build_general_account(code: "701001", name: "Bar", klass: 7, nature: "revenue") }
  let!(:cash_account) { build_cash_account(entity, bank_account) }
  let!(:entry) do
    build_cash_entry(cash_account, amount_cents: 450, label: "Payconiq").tap do |e|
      e.update!(counterparty_name: "DUPONT MARIE", communication: "consos")
    end
  end
  let(:jev) { MailIntakeHelpers::FakeJev.new { |_id, _q| { "choice" => bar.to_s, "confidence" => 0.93 } } }

  before do
    sign_in user
    Finance::AllocationHistory.reset!
    precedent = build_cash_entry(cash_account, amount_cents: 350, entry_date: Date.new(2026, 5, 2), label: "Payconiq")
    precedent.update!(counterparty_name: "DUPONT MARIE", communication: "consos bar")
    allocate(precedent, account: bar, amount_cents: 350, entity: entity)
    Accounting::PostCashEntry.new(cash_entry: precedent).run!
  end

  it "pose un cadre chargé à la volée sur une ligne sans règle quand Jev est configuré" do
    allow(Jev::Client).to receive(:api_key).and_return("cle-de-test")

    get finance_unallocated_cash_entries_path

    expect(response.body).to include(%(src="#{suggestion_finance_cash_entry_path(entry)}"))
    expect(response.body).to include("Jev cherche une proposition")
  end

  it "ne pose aucun cadre sans clé TypeSafe" do
    allow(Jev::Client).to receive(:api_key).and_return(nil)

    get finance_unallocated_cash_entries_path

    expect(response.body).not_to include(suggestion_finance_cash_entry_path(entry))
  end

  it "rend la proposition de Jev dans le cadre de la ligne, qui sort vers la page entière" do
    allow(Jev::Client).to receive(:new).and_return(jev)

    get suggestion_finance_cash_entry_path(entry)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(%(id="suggestion_cash_entry_#{entry.id}"))
    expect(response.body).to include(%(target="_top"))
    expect(response.body).to include("701001 Bar")
    expect(response.body).to include("Jev, 93 % de confiance")
    expect(entry.reload.allocation_suggestions.pending.first.source).to eq("jev")
  end

  it "rend un cadre vide quand Jev n'est pas assez sûr, puis ne le repose plus" do
    allow(Jev::Client).to receive(:new).and_return(
      MailIntakeHelpers::FakeJev.new { |_id, _q| { "choice" => bar.to_s, "confidence" => 0.55 } }
    )

    get suggestion_finance_cash_entry_path(entry)
    expect(response.body).not_to include("Proposition")

    allow(Jev::Client).to receive(:api_key).and_return("cle-de-test")
    get finance_unallocated_cash_entries_path
    expect(response.body).not_to include(suggestion_finance_cash_entry_path(entry))
  end
end
