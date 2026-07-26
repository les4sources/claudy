require "rails_helper"

# Index admin des séjours (epic #81) — le séjour est le point d'entrée unique :
# tableau paginé (30/page) orienté gestion des réservations et paiements, avec
# filtres légers et boutons de transition vers les anciennes vues.
RSpec.describe "Index Séjours (/stays)", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user) { User.create!(email: "agent-index@les4sources.be", password: "password123") }
  before { sign_in user }

  # Crée un séjour daté rattaché à un client distinct (email unique obligatoire).
  def create_stay(email:, arrival:, departure:, total_cents: 0, first: "Jean", last: "Test")
    customer = Customer.create!(email: email, first_name: first, last_name: last)
    Stay.create!(
      customer:           customer,
      source:             "manual",
      status:             "pending",
      arrival_date:       arrival,
      departure_date:     departure,
      total_amount_cents: total_cents
    )
  end

  describe "garde Devise" do
    it "redirige un visiteur non authentifié vers sign_in" do
      sign_out user
      get stays_path
      expect(response).to redirect_to("/users/sign_in")
    end
  end

  describe "rendu et contenu de gestion" do
    let!(:stay) do
      create_stay(email: "cliente@example.com", first: "Alice", last: "Durand",
                  arrival: Date.today + 5, departure: Date.today + 7, total_cents: 12_345)
    end

    it "répond 200 et affiche client et total" do
      get stays_path
      expect(response).to have_http_status(:ok)
      # Client (nom + email)
      expect(response.body).to include("Alice Durand")
      expect(response.body).to include("cliente@example.com")
      # Total formaté (même helper que la vue → indépendant de la locale de test)
      expected_total = ApplicationController.helpers.humanized_money_with_symbol(Money.new(12_345))
      expect(response.body).to include(expected_total)
      # Plus de colonne « Paiement » (Michael 2026-07-26) : l'état de paiement se
      # lit dans la colonne Montant (solde dû en rouge / check vert).
      expect(response.body).not_to include(I18n.t("public.stays.payment_status.pending"))
    end

    it "affiche les boutons vers les anciennes vues (transition)" do
      get stays_path
      expect(response.body).to include("Hébergements (ancienne vue)")
      expect(response.body).to include("Espaces (ancienne vue)")
      expect(response.body).to include(%(href="#{bookings_path}"))
      expect(response.body).to include(%(href="#{space_bookings_path}"))
    end
  end

  # Le trimestre EST la page (Michael 2026-07-26) : plus de découpe par nombre.
  describe "pagination trimestrielle" do
    let(:trimestre) { Date.today.beginning_of_quarter }

    before do
      # 31 séjours dans le trimestre courant : tous doivent tenir sur une page.
      31.times do |i|
        create_stay(email: "p#{i}@example.com",
                    arrival: trimestre + i.days, departure: trimestre + i.days + 1)
      end
      # Un séjour du trimestre SUIVANT, qui ne doit pas apparaître.
      create_stay(email: "suivant@example.com", first: "Trimestre", last: "Suivant",
                  arrival: trimestre + 4.months, departure: trimestre + 4.months + 1.day)
    end

    it "affiche TOUT le trimestre sur une seule page" do
      get stays_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("31 séjours sur ce trimestre")
    end

    it "n'affiche pas les séjours d'un autre trimestre" do
      get stays_path
      expect(response.body).not_to include("Trimestre Suivant")
    end

    it "navigue vers un trimestre donné" do
      suivant = trimestre + 3.months
      get stays_path(year: suivant.year, quarter: ((suivant.month - 1) / 3) + 1)
      expect(response.body).to include("Trimestre Suivant")
    end
  end

  describe "navigation trimestrielle" do
    let(:trimestre) { Date.today.beginning_of_quarter }

    it "ouvre sur le trimestre courant" do
      get stays_path
      # L'année et le trimestre sont deux éléments distincts du sélecteur.
      expect(response.body).to include(">#{trimestre.year}</span>")
      expect(response.body).to include(%(aria-current="page"))
    end

    it "ne propose plus les anciennes pastilles de période" do
      get stays_path
      expect(response.body).not_to include(">À venir<")
      expect(response.body).not_to include(">Passés<")
    end

    it "retombe sur le trimestre courant pour des paramètres fantaisistes" do
      get stays_path(year: "abc", quarter: "9")
      expect(response).to have_http_status(:ok)
      # L'année et le trimestre sont deux éléments distincts du sélecteur.
      expect(response.body).to include(">#{trimestre.year}</span>")
      expect(response.body).to include(%(aria-current="page"))
    end
  end
end
