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

    it "répond 200 et affiche client, total et badge de paiement" do
      get stays_path
      expect(response).to have_http_status(:ok)
      # Client (nom + email)
      expect(response.body).to include("Alice Durand")
      expect(response.body).to include("cliente@example.com")
      # Total formaté (même helper que la vue → indépendant de la locale de test)
      expected_total = ApplicationController.helpers.humanized_money_with_symbol(Money.new(12_345))
      expect(response.body).to include(expected_total)
      # Badge de statut de paiement (défaut « pending »)
      expect(response.body).to include(I18n.t("public.stays.payment_status.pending"))
    end

    it "affiche les boutons vers les anciennes vues (transition)" do
      get stays_path
      expect(response.body).to include("Hébergements (ancienne vue)")
      expect(response.body).to include("Espaces (ancienne vue)")
      expect(response.body).to include(%(href="#{bookings_path}"))
      expect(response.body).to include(%(href="#{space_bookings_path}"))
    end
  end

  describe "pagination 30/page" do
    before do
      31.times do |i|
        create_stay(email: "p#{i}@example.com",
                    arrival: Date.today + 1 + i, departure: Date.today + 2 + i)
      end
    end

    it "affiche 30 séjours sur la première page (« 1–30 sur 31 »)" do
      get stays_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("1–30 sur 31")
    end

    it "affiche le 31e séjour sur la seconde page (« 31–31 sur 31 »)" do
      get stays_path(page: 2)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("31–31 sur 31")
    end
  end

  describe "filtre « À venir »" do
    let!(:future_stay) do
      create_stay(email: "future@example.com", first: "Futur", last: "Client",
                  arrival: Date.today + 10, departure: Date.today + 12)
    end
    let!(:past_stay) do
      create_stay(email: "passe@example.com", first: "Passe", last: "Client",
                  arrival: Date.today - 12, departure: Date.today - 10)
    end

    it "n'affiche pas un séjour passé" do
      get stays_path(filter: "upcoming")
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Futur Client")
      expect(response.body).not_to include("Passe Client")
    end
  end
end
