require "rails_helper"
require Rails.root.join("spec/support/finance_builders")

# « J'ai affecté une ligne et j'ai oublié de la ventiler différemment »
# (Michael, 2026-10-19) : modifier la ventilation d'une ligne, même
# comptabilisée, depuis sa fiche.
RSpec.describe "Comptabilité — modifier la ventilation d'une ligne", type: :request do
  include FinanceBuilders

  let(:user) { User.create!(email: "compta@les4sources.be", password: "password123") }
  let(:entity) { build_legal_entity }
  let!(:fiscal_year) { build_fiscal_year(entity) }
  let!(:hebergement) { build_general_account(code: "700000", name: "Hébergement", klass: 7, nature: "revenue") }
  let!(:bar) { build_general_account(code: "700100", name: "Ventes bar", klass: 7, nature: "revenue") }
  let!(:bank) { build_cash_account(entity, build_general_account(code: "550000", name: "Banque")) }
  let!(:cuisine) { Team.create!(name: "Pôle Cuisine", kind: "economic") }
  let!(:entry) { build_cash_entry(bank, amount_cents: 30_000) }
  let!(:part_existante) { allocate(entry, account: hebergement, amount_cents: 30_000, entity: entity) }

  before do
    Accounting::PostCashEntry.new(cash_entry: entry).run!
    sign_in user
  end

  it "propose le geste sur la fiche de la ligne" do
    get finance_cash_entry_path(entry)

    expect(response.body).to include("Modifier la ventilation", edit_finance_cash_entry_reallocation_path(entry))
  end

  it "montre les parts de la ligne, prêtes à corriger, avec l'aide de l'écran" do
    get edit_finance_cash_entry_reallocation_path(entry)

    expect(response).to have_http_status(:ok)
    html = Nokogiri::HTML(response.body)
    expect(html.at_css("input[name='parts[#{part_existante.id}][id]']")["value"]).to eq(part_existante.id.to_s)
    expect(html.at_css("input[name='parts[#{part_existante.id}][amount]']")["value"]).to eq("300,00")
    expect(html.at_css("[data-page-guide]").text).to include("Corriger la ventilation")
    expect(CGI.unescapeHTML(response.body)).to include("son écriture sera contre-passée")
  end

  it "enregistre la nouvelle ventilation et recomptabilise la ligne" do
    patch finance_cash_entry_reallocation_path(entry), params: {
      parts: {
        part_existante.id.to_s => { id: part_existante.id, general_account_id: hebergement.id, team_id: "",
                                    legal_entity_id: entity.id, amount: "200,00" },
        "17290000001" => { general_account_id: bar.id, team_id: cuisine.id, legal_entity_id: entity.id, amount: "100" }
      }
    }

    expect(response).to redirect_to(finance_cash_entry_path(entry))
    expect(flash[:notice]).to eq("Ventilation modifiée : l'ancienne écriture est contre-passée, la nouvelle est au grand livre.")
    expect(entry.reload).to be_posted
    expect(entry.cash_allocations.map { |a| [a.general_account, a.team, a.amount_cents] })
      .to contain_exactly([hebergement, nil, 20_000], [bar, cuisine, 10_000])
  end

  it "réaffiche la saisie refusée avec sa raison, sans rien toucher" do
    patch finance_cash_entry_reallocation_path(entry), params: {
      parts: {
        part_existante.id.to_s => { id: part_existante.id, general_account_id: hebergement.id,
                                    legal_entity_id: entity.id, amount: "250" },
        "17290000001" => { general_account_id: bar.id, legal_entity_id: entity.id, amount: "100" }
      }
    }

    expect(response).to have_http_status(:unprocessable_content)
    expect(CGI.unescapeHTML(response.body)).to include("Les 2 parts font 350 €, la ligne fait 300 €. Rien n'a été modifié.")
    html = Nokogiri::HTML(response.body)
    expect(html.at_css("input[name='parts[#{part_existante.id}][amount]']")["value"]).to eq("250,00")
    expect(html.css("[data-allocation-parts-target='list'] input[value='100,00']")).to be_present
    expect(entry.reload).to be_posted
    expect(part_existante.reload.amount_cents).to eq(30_000)
  end
end
