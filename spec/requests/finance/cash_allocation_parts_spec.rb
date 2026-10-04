require "rails_helper"
require Rails.root.join("spec/support/finance_builders")

# Epic #288, phase 6 — répartir une ligne sur plusieurs comptes et pôles depuis
# la file. Les parts s'enregistrent ensemble ou pas du tout.
RSpec.describe "Comptabilité — répartir une ligne en plusieurs parts", type: :request do
  include Devise::Test::IntegrationHelpers
  include FinanceBuilders

  let(:user) { User.create!(email: "compta@les4sources.be", password: "password123") }
  let(:entity) { build_legal_entity }
  let!(:fiscal_year) { build_fiscal_year(entity) }
  let!(:hebergement) { build_general_account(code: "700000", name: "Hébergement", klass: 7, nature: "revenue") }
  let!(:bar) { build_general_account(code: "700100", name: "Ventes bar", klass: 7, nature: "revenue") }
  let!(:salle) { build_general_account(code: "700200", name: "Location salle", klass: 7, nature: "revenue") }
  let!(:bank) { build_cash_account(entity, build_general_account(code: "550000", name: "Banque")) }
  let!(:accueil) { Team.create!(name: "Pôle Accueil", kind: "economic") }
  let!(:cuisine) { Team.create!(name: "Pôle Cuisine", kind: "economic") }
  let!(:entry) { build_cash_entry(bank, amount_cents: 30_000) }

  before { sign_in user }

  def part(account, montant, team: nil)
    { general_account_id: account.id, team_id: team&.id, legal_entity_id: entity.id, amount: montant }
  end

  def envoyer(premiere, *suivantes, depuis_la_file: true)
    params = { cash_allocation: premiere }
    params[:parts] = suivantes.each_with_index.to_h { |p, i| [i.to_s, p] } if suivantes.any?
    params[:from_unallocated] = "1" if depuis_la_file
    headers = if depuis_la_file
                { "Accept" => "text/vnd.turbo-stream.html, text/html",
                  "Referer" => "http://www.example.com#{finance_unallocated_cash_entries_path(page: 2)}" }
              else
                {}
              end
    post finance_cash_entry_allocations_path(entry), params: params, headers: headers
  end

  it "enregistre toutes les parts et comptabilise la ligne quand elles la couvrent" do
    envoyer(part(hebergement, "180,00", team: accueil), part(bar, "70,00", team: cuisine), part(salle, "50"))

    expect(entry.cash_allocations.reload.map { |a| [a.general_account, a.team, a.amount_cents] })
      .to contain_exactly([hebergement, accueil, 18_000], [bar, cuisine, 7_000], [salle, nil, 5_000])
    expect(entry.reload).to be_posted
    expect(response.media_type).to eq("text/vnd.turbo-stream.html")
    expect(response.body).to include(%(<turbo-stream action="remove" target="file-ligne-#{entry.id}">))
  end

  it "n'enregistre AUCUNE part quand leur somme dépasse la ligne, et le dit sur la ligne" do
    expect do
      envoyer(part(hebergement, "200"), part(bar, "70"), part(salle, "50"))
    end.not_to change(CashAllocation, :count)

    expect(entry.reload.status).to eq("pending")
    expect(response.body).to include(%(<turbo-stream action="replace" target="file-ligne-#{entry.id}">))
    expect(response.body).to include("Les 3 parts font 320 €, il ne reste que 300 € à affecter. Rien n&#39;a été enregistré.")
  end

  it "laisse la ligne en attente avec son reste quand les parts ne la couvrent pas" do
    envoyer(part(hebergement, "100"), part(bar, "50"))

    expect(entry.cash_allocations.reload.sum(:amount_cents)).to eq(15_000)
    expect(entry.reload.status).to eq("pending")
    expect(entry.remaining_cents).to eq(15_000)
    expect(response.body).to include("il reste 150 € à affecter")
    # Les parts posées se voient dans la ligne redessinée.
    expect(response.body).to include("Déjà affecté")
    expect(response.body).to include("700100 Ventes bar")
  end

  it "refuse tout le découpage quand une part va dans le sens contraire" do
    expect do
      envoyer(part(hebergement, "100"), part(bar, "-50"))
    end.not_to change(CashAllocation, :count)

    expect(response.body).to include("Part 2 :")
    expect(response.body).to include("va dans le sens contraire du mouvement")
  end

  it "refuse tout le découpage quand une part n'a pas de compte" do
    expect do
      envoyer(part(hebergement, "100"), { general_account_id: "", legal_entity_id: entity.id, amount: "50" })
    end.not_to change(CashAllocation, :count)

    expect(response.body).to include("Part 2 :")
  end

  it "garde le cas simple à l'identique, depuis la file" do
    envoyer(part(hebergement, "300,00"))

    expect(entry.reload).to be_posted
    expect(entry.cash_allocations.count).to eq(1)
  end

  it "garde le cas simple à l'identique, depuis la page de la ligne" do
    envoyer(part(hebergement, "100"), depuis_la_file: false)

    expect(response).to redirect_to(finance_cash_entry_path(entry))
    expect(entry.reload.remaining_cents).to eq(20_000)
  end

  it "répartit aussi depuis la page de la ligne" do
    envoyer(part(hebergement, "100"), part(bar, "200"), depuis_la_file: false)

    expect(response).to redirect_to(finance_cash_entry_path(entry))
    expect(entry.reload).to be_posted
  end

  it "propose d'ajouter une part dans le formulaire de la file" do
    get finance_unallocated_cash_entries_path

    expect(response.body).to include("+ Ajouter une part")
    expect(response.body).to include("parts[__INDEX__][general_account_id]")
    expect(response.body).to include(%(data-allocation-parts-remaining-value="30000"))
  end
end
