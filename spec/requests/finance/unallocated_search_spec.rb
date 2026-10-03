require "rails_helper"
require Rails.root.join("spec/support/finance_builders")

# Epic #288, phase 4 — chercher et filtrer dans la file « À affecter ». On ne
# classe pas dix mille lignes dans l'ordre d'arrivée : on les classe par lots
# qui se ressemblent.
RSpec.describe "Comptabilité — À affecter, recherche et filtres", type: :request do
  include Devise::Test::IntegrationHelpers
  include FinanceBuilders

  let(:user) { User.create!(email: "compta@les4sources.be", password: "password123") }
  let(:entity) { build_legal_entity }
  let!(:fiscal_year) { build_fiscal_year(entity) }
  let!(:revenue) { build_general_account(code: "700000", name: "Hébergement", klass: 7, nature: "revenue") }
  let!(:bank) { build_cash_account(entity, build_general_account(code: "550000", name: "Banque")) }
  let!(:bar) do
    build_cash_entry(bank, amount_cents: 2_450, label: "Ligne bar").tap do |e|
      e.update!(communication: "Bar Épicerie juin", counterparty_name: "Hélène Dupont")
    end
  end
  let!(:loyer) do
    build_cash_entry(bank, amount_cents: -80_000, label: "Ligne loyer").tap do |e|
      e.update!(communication: "Loyer juin", counterparty_name: "Propriétaire SA")
    end
  end

  before { sign_in user }

  it "réduit la liste et le compteur à la recherche, sans casse ni accents" do
    get finance_unallocated_cash_entries_path(q: "EPICERIE")

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Bar Épicerie juin")
    expect(response.body).not_to include("Loyer juin")
    expect(response.body).to include("1 ligne(s) en attente")
    expect(response.body).to include("1 ligne(s) sur 2 en attente")
  end

  it "montre chaque filtre actif, retirable seul" do
    get finance_unallocated_cash_entries_path(q: "juin", sens: "out")

    expect(response.body).to include("Loyer juin")
    expect(response.body).not_to include("Bar Épicerie juin")
    expect(response.body).to include("« juin »")
    expect(response.body).to include("Sorties")
    # Retirer le sens garde la recherche, et inversement.
    expect(response.body).to include(%(href="#{finance_unallocated_cash_entries_path(q: 'juin')}"))
    expect(response.body).to include(%(href="#{finance_unallocated_cash_entries_path(sens: 'out')}"))
  end

  it "filtre par période et par montant" do
    loyer.update!(entry_date: Date.new(2026, 5, 2))

    get finance_unallocated_cash_entries_path(from: "2026-06-01", to: "2026-06-30")
    expect(response.body).to include("Bar Épicerie juin")
    expect(response.body).not_to include("Loyer juin")

    get finance_unallocated_cash_entries_path(min: "100")
    expect(response.body).to include("Loyer juin")
    expect(response.body).not_to include("Bar Épicerie juin")
  end

  it "dit clairement qu'aucune ligne ne correspond, et propose de retirer les filtres" do
    get finance_unallocated_cash_entries_path(q: "zzzintrouvable", sens: "in")

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Aucune ligne en attente ne correspond à ces filtres.")
    expect(response.body).to include("Retirer les filtres")
    expect(response.body).not_to include("Rien à affecter")
  end

  it "garde les filtres dans les liens de pagination" do
    (Finance::UnallocatedQueue::PAR_PAGE + 1).times do |n|
      build_cash_entry(bank, amount_cents: 1_000 + n).update!(communication: "Bar soirée #{n}")
    end

    get finance_unallocated_cash_entries_path(q: "bar")

    expect(response.body).to include("page 1 sur 2")
    expect(response.body).to match(/href="[^"]*q=bar[^"]*page=2|href="[^"]*page=2[^"]*q=bar/)
  end

  it "borne le calcul des suggestions aux lignes affichées, même filtrées" do
    (Finance::UnallocatedQueue::PAR_PAGE + 5).times do |n|
      build_cash_entry(bank, amount_cents: 1_000 + n).update!(communication: "Bar soirée #{n}")
    end

    expect { get finance_unallocated_cash_entries_path(q: "bar") }
      .to change { AllocationSuggestion.count }.by_at_most(Finance::UnallocatedQueue::PAR_PAGE)
  end

  # Affecter depuis une vue filtrée : la ligne sort, et le compteur compte ce
  # qui reste DANS la vue, pas toute la file.
  it "compte ce qui reste dans la vue filtrée après une affectation" do
    post finance_cash_entry_allocations_path(bar),
         params: { from_unallocated: "1",
                   cash_allocation: { general_account_id: revenue.id, legal_entity_id: entity.id, amount: "24,50" } },
         headers: { "Accept" => "text/vnd.turbo-stream.html, text/html",
                    "Referer" => "http://www.example.com#{finance_unallocated_cash_entries_path(q: 'epicerie', page: 1)}" }

    expect(response.media_type).to eq("text/vnd.turbo-stream.html")
    expect(response.body).to include(%(<turbo-stream action="remove" target="file-ligne-#{bar.id}">))
    expect(response.body).to include("0 ligne(s) en attente")
    expect(response.body).to include("0 ligne(s) sur 1 en attente.")
  end
end
