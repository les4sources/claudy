require "rails_helper"

# Issue #323 — le tableau de bord d'UN MEMBRE.
#
# Réunion Pôle Accueil × Cuisine du 2026-09-11. La page existait à moitié : elle
# n'affichait que les tâches du `Human` du compte connecté, et PLANTAIT quand le
# compte n'en avait pas. Elle devient la vue d'un membre désigné, avec sélecteur.
RSpec.describe "Tableau de bord d'un membre", type: :request do
  include Devise::Test::IntegrationHelpers

  let!(:steph)  { Human.create!(name: "Stéphanie Cuisine", email: "steph-dash@les4sources.be", status: "active") }
  let!(:malau)  { Human.create!(name: "Malau Accueil", email: "malau-dash@les4sources.be", status: "active") }

  let(:user_steph)  { User.create!(email: "steph-dash-user@les4sources.be", password: "password123", human: steph) }
  let(:user_global) { User.create!(email: "accueil-dash@les4sources.be", password: "password123") }

  let(:customer) { Customer.create!(email: "dash-client@example.com", first_name: "Groupe", last_name: "Godinne") }
  let(:stay) do
    Stay.create!(customer: customer, source: "manual", status: "confirmed",
                 arrival_date: Date.current + 10, departure_date: Date.current + 12)
  end

  def order(**attrs)
    MealOrder.create!({ kind: "repas", people: 8, stay: stay, moment: "midi",
                        skip_notifications: true }.merge(attrs))
  end

  describe "qui on regarde" do
    it "ouvre sur SA propre vue quand le compte est rattaché à un membre" do
      sign_in user_steph
      get dashboard_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Tableau de bord de Stéphanie Cuisine")
    end

    # Le plantage corrigé : `current_user.human.tasks` sur `nil`.
    it "rend la page et le sélecteur — jamais une 500 — sur un compte non rattaché" do
      sign_in user_global
      get dashboard_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Choisissez un membre")
      expect(response.body).to include("Stéphanie Cuisine")
      expect(response.body).to include("Malau Accueil")
    end

    it "affiche la vue d'un AUTRE membre quand human_id est passé" do
      sign_in user_steph
      get dashboard_path(human_id: malau.id)

      expect(response.body).to include("Tableau de bord de Malau Accueil")
    end

    it "retombe sur le sélecteur seul quand human_id ne désigne personne" do
      sign_in user_steph
      get dashboard_path(human_id: 0)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Choisissez un membre")
    end
  end

  describe "le contenu des blocs" do
    before { sign_in user_steph }

    # Un jeu couvrant les quatre cas : chaque ligne doit tomber dans UN bloc et
    # dans aucun autre — c'est la seule façon de prouver que les filtres ne se
    # recouvrent pas.
    let!(:a_traiter) do
      order(notes: "BUFFET A TRAITER", date: Date.current + 10,
            validation: "pending", status: "requested", responsible_human: steph)
    end
    let!(:prochain) do
      order(notes: "SERVICE A VENIR", date: Date.current + 11,
            validation: "accepted", status: "confirmed", responsible_human: steph)
    end
    let!(:attente_client) do
      order(notes: "ATTENTE CLIENT", date: Date.current + 12,
            validation: "accepted", status: "requested", responsible_human: steph)
    end
    let!(:passe) do
      order(notes: "SERVICE PASSE", date: Date.current - 5,
            validation: "accepted", status: "confirmed", responsible_human: steph)
    end
    let!(:autre_responsable) do
      order(notes: "LIGNE DE MALAU", date: Date.current + 10,
            validation: "pending", status: "requested", responsible_human: malau)
    end

    it "range chaque ligne dans son bloc, et seulement dans le sien" do
      get dashboard_path

      body = response.body
      expect(body).to include("À traiter")
      expect(body).to include("Mes prochains services")
      expect(body).to include("En attente du client")
      expect(body).to include("Mes tâches")

      expect(body).to include("BUFFET A TRAITER")
      expect(body).to include("SERVICE A VENIR")
      expect(body).to include("ATTENTE CLIENT")
    end

    it "laisse dehors ce qui est passé" do
      get dashboard_path

      expect(response.body).not_to include("SERVICE PASSE")
    end

    # Le point qui fait toute la valeur de la page : la ligne d'un AUTRE
    # responsable n'apparaît jamais.
    it "n'affiche jamais la ligne d'un autre responsable" do
      get dashboard_path

      expect(response.body).not_to include("LIGNE DE MALAU")
    end

    it "affiche le total de convives du jour sur les prochains services" do
      order(notes: "DEUXIEME SERVICE", date: Date.current + 11, people: 4,
            validation: "accepted", status: "confirmed", responsible_human: steph)

      get dashboard_path

      expect(response.body).to include("12 couverts")
    end

    it "dit son vide plutôt que de disparaître quand un bloc n'a rien" do
      get dashboard_path(human_id: malau.id)

      expect(response.body).to include("Aucun service à venir.")
      expect(response.body).to include("Rien en attente du client.")
    end

    # Les prix sont l'affaire du Pôle Accueil, comme sur la page Cuisine.
    it "n'affiche aucun montant" do
      a_traiter.update!(unit_price_cents: 2_500)

      get dashboard_path

      expect(response.body).not_to match(/\d+[,.]\d{2}\s*€/)
    end
  end

  describe "les gestes" do
    before { sign_in user_steph }

    let!(:a_traiter) do
      order(notes: "A ACCEPTER", date: Date.current + 10,
            validation: "pending", status: "requested", responsible_human: steph)
    end

    it "« Ok ! » accepte la ligne et revient sur le tableau de bord" do
      patch accept_kitchen_order_path(a_traiter), headers: { "HTTP_REFERER" => dashboard_url }

      expect(a_traiter.reload.validation).to eq("accepted")
      expect(response).to redirect_to(dashboard_url)
    end
  end

  # Le cloisonnement des activités (PR #262) ne doit pas se contourner par une
  # porte nouvelle : `pages` n'est pas dans l'allowlist de `BaseController`, un
  # compte restreint est donc renvoyé sur son planning — ni sa vue, ni celle
  # d'un autre membre via le sélecteur.
  describe "le cloisonnement" do
    let(:porteur) do
      User.create!(email: "porteur-dash@les4sources.be", password: "password123",
                   human: malau, restricted_to_experiences: true)
    end

    before { sign_in porteur }

    it "renvoie un compte cloisonné sur son planning, sans bloc cuisine" do
      get dashboard_path

      expect(response).to redirect_to(experiences_path)
    end

    it "ne laisse pas non plus regarder un autre membre via le sélecteur" do
      get dashboard_path(human_id: steph.id)

      expect(response).to redirect_to(experiences_path)
    end
  end
end
