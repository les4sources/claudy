require "rails_helper"
require Rails.root.join("spec/support/finance_builders")

# « Peut-on dépenser ? » (Michael, 2026-10-19) : chaque montant qui a une
# liste derrière l'ouvre en fenêtre, et la liste fait le même total que
# l'encart.
RSpec.describe "Comptabilité > Peut-on dépenser ? > détail", type: :request do
  include FinanceBuilders

  let(:user) { User.create!(email: "compta-verdict@les4sources.be", password: "password123") }
  let!(:entity) { build_legal_entity(name: "Fondation Les 4 Sources") }
  let!(:fiscal_year) { build_fiscal_year(entity) }
  let(:bank_general) { build_general_account(code: "550000", name: "Triodos") }
  let!(:bank) { build_cash_account(entity, bank_general, name: "Triodos") }
  let(:customer) { Customer.create!(first_name: "Jeanne", last_name: "Dupont", email: "jeanne@example.test") }

  before do
    sign_in user
    import = CodaImport.create!(filename: "r.cod", sha256: SecureRandom.hex(32), content: "x")
    CodaStatement.create!(coda_import: import, cash_account: bank, sequence_number: "001", period_year: 2026,
                          old_balance_cents: 0, new_balance_cents: 4_748_100, new_balance_date: Date.current)
  end

  def stay(arrival:, departure:, total:)
    Stay.create!(customer: customer, arrival_date: arrival, departure_date: departure,
                 total_amount_cents: total, payment_status: "pending", status: "confirmed")
  end

  def frame_get(part)
    get finance_accounting_verdict_detail_path(entity, part), headers: { "Turbo-Frame" => "modal" }
    Nokogiri::HTML(response.body)
  end

  def verdict = Finance::SpendingVerdict.new(legal_entity: entity)

  it "rend chaque montant cliquable, ouvert dans la fenêtre" do
    stay(arrival: Date.current + 10, departure: Date.current + 12, total: 60_000)
    Liability.create!(legal_entity: entity, label: "Taxe d'hébergement", retained_cents: 1_200_000,
                      expected_on: Date.current + 30, installments: 6)
    pret = build_general_account(code: "174004", name: "Prêt court terme Sourciers", klass: 1, nature: "liability")
    post_simple_entry(entity: entity, debit_account: bank_general, credit_account: pret, amount_cents: 500_000)

    get finance_accounting_path

    liens = Nokogiri::HTML(response.body).css("[data-spending-detail]")
    expect(liens.map { |a| a["data-spending-detail"] }).to eq(%w[incoming outgoing liabilities_later loans])
    expect(liens.map { |a| a["data-turbo-frame"] }.uniq).to eq(["modal"])
    expect(liens.map { |a| a["href"] }).to all(start_with("/finance/accounting/verdict/#{entity.id}/"))
  end

  it "laisse un montant nul en simple texte" do
    get finance_accounting_path

    expect(Nokogiri::HTML(response.body).css("[data-spending-detail]")).to be_empty
  end

  it "détaille ce qui est à encaisser, séjours en retard puis à venir" do
    a_venir = stay(arrival: Date.current + 10, departure: Date.current + 12, total: 60_000)
    en_retard = stay(arrival: Date.current - 60, departure: Date.current - 58, total: 20_000)
    stay(arrival: Date.current + 200, departure: Date.current + 202, total: 99_000)

    html = frame_get("incoming")

    expect(response).to have_http_status(:ok)
    expect(html.at_css("turbo-frame#modal")).to be_present
    expect(html.css("[data-verdict-detail='incoming'] tr[data-stay-id]").map { |tr| tr["data-stay-id"].to_i })
      .to eq([en_retard.id, a_venir.id])
    expect(html.text).to include("800,00 €")
    expect(verdict.incoming_cents).to eq(80_000)
  end

  it "détaille ce qui est à payer, rangé par nature" do
    RecurringExpense.create!(legal_entity: entity, label: "Loyer", amount_cents: 50_000, frequency: "monthly",
                             first_due_on: Date.current + 1)
    Liability.create!(legal_entity: entity, label: "Arriéré Voo", retained_cents: 20_000)

    html = frame_get("outgoing")
    corps = html.text

    expect(corps).to include("Charges fixes", "Loyer", "Dettes et litiges sans facture", "Arriéré Voo")
    total = html.at_css("tfoot td.text-right").text
    expect(total).to eq(ApplicationController.helpers.number_to_currency(verdict.outgoing_cents / 100.0, unit: "€"))
  end

  it "détaille les dettes et litiges qui tombent après l'horizon" do
    dette = Liability.create!(legal_entity: entity, label: "Taxe d'hébergement", retained_cents: 1_200_000,
                              expected_on: Date.current + 30, installments: 6)

    html = frame_get("liabilities_later")

    ligne = html.at_css("tr[data-liability-id='#{dette.id}']")
    expect(ligne.text).to include("Taxe d'hébergement", "4 mensualités")
    expect(ligne.at_css("a")["data-turbo-frame"]).to eq("_top")
    expect(verdict.liabilities_later_cents).to eq(800_000)
  end

  it "détaille les prêts à rendre, sans les prêts à long terme" do
    pret = build_general_account(code: "174004", name: "Prêt court terme Sourciers", klass: 1, nature: "liability")
    certificats = build_general_account(code: "174001", name: "Certificat immobilier", klass: 1, nature: "liability")
    certificats.update!(long_term: true)
    post_simple_entry(entity: entity, debit_account: bank_general, credit_account: pret, amount_cents: 500_000)
    post_simple_entry(entity: entity, debit_account: bank_general, credit_account: certificats, amount_cents: 7_500_000)

    html = frame_get("loans")
    corps = CGI.unescapeHTML(html.text)

    expect(corps).to include("174004 Prêt court terme Sourciers")
    expect(corps).not_to include("174001 Certificat immobilier")
    expect(corps).to include("Les prêts à long terme (75 000 €) n'y sont pas")
  end

  it "refuse une partie inconnue" do
    expect { get "/finance/accounting/verdict/#{entity.id}/balance" }.to raise_error(ActionController::RoutingError)
  end
end
