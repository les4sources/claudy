require "rails_helper"

# Poste de travail FACTURATION (Michael 2026-07-26) — remplace
# « Comptabilité / Tableau de bord ». Une seule file normalisée pour les deux
# modèles facturables (Booking + SpaceBooking), et le passage « à fournir » →
# « envoyée » sans quitter la page.
RSpec.describe "Facturation (/invoicing)", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user) { User.create!(email: "admin-factu@les4sources.be", password: "password123") }
  before { sign_in user }

  def booking(invoice_status:, group: "Groupe héb.", price_cents: 15_000, tier: nil,
              status: "confirmed", from_date: Date.today + 3)
    Booking.create!(firstname: "T", group_name: group, adults: 2,
                    from_date: from_date, to_date: from_date + 2,
                    status: status, invoice_status: invoice_status,
                    price_cents: price_cents, tier: tier)
  end

  def space_booking(invoice_status:, group: "Groupe espace", price_cents: 8_000, tier: nil,
                    status: "confirmed", from_date: Date.today + 3)
    SpaceBooking.create!(firstname: "T", group_name: group,
                         from_date: from_date, to_date: from_date + 2,
                         status: status, invoice_status: invoice_status,
                         price_cents: price_cents, tier: tier)
  end

  def stay(invoice_status:, status: "confirmed", first_name: "Fanny")
    customer = Customer.create!(email: "#{first_name.parameterize}@example.com", first_name: first_name, last_name: "Séjour")
    Stay.create!(customer: customer, source: "manual", status: status,
                 arrival_date: Date.today + 3, departure_date: Date.today + 5,
                 total_amount_cents: 45_000, invoice_status: invoice_status)
  end

  describe "garde Devise" do
    it "redirige un visiteur non authentifié" do
      sign_out user
      get invoicing_path
      expect(response).to redirect_to("/users/sign_in")
    end
  end

  describe "file « à fournir »" do
    it "réunit hébergements ET espaces dans une seule file" do
      booking(invoice_status: "requested", group: "Chorale de Dinant")
      space_booking(invoice_status: "requested", group: "Fanfare communale")

      get invoicing_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Chorale de Dinant")
      expect(response.body).to include("Fanfare communale")
      # Le compteur et son libellé sont deux éléments distincts (chiffre en gros,
      # libellé en dessous) : on vérifie les deux, pas une chaîne accolée.
      expect(response.body).to include(">2</span>")
      expect(response.body).to include("factures à fournir")
    end

    it "annonce une file vide plutôt que d'afficher un tableau vide" do
      get invoicing_path
      expect(response.body).to include("Aucune facture en attente")
    end

    it "n'affiche pas les factures non requises" do
      booking(invoice_status: "on", group: "Pas concerné")
      get invoicing_path
      expect(response.body).not_to include("Pas concerné")
    end

    it "signale une ligne sans montant — la facture ne peut pas être émise" do
      booking(invoice_status: "requested", group: "Sans prix", price_cents: 0)
      get invoicing_path
      expect(response.body).to include("montant à définir")
    end

    # Une réservation annulée ne se facture pas (Michael 2026-09-06) : la file
    # affichait des séjours annulés comme du travail à faire. Les deux
    # orthographes de l'annulation sont couvertes (cf. `Invoicing::Queue::CANCELED_STATUSES`).
    it "n'affiche pas les réservations annulées, quel que soit le modèle" do
      booking(invoice_status: "requested", group: "Hébergement annulé", status: "canceled")
      space_booking(invoice_status: "requested", group: "Espace annulé", status: "cancelled")
      stay(invoice_status: "requested", status: "canceled", first_name: "Annulée")

      get invoicing_path
      expect(response.body).not_to include("Hébergement annulé")
      expect(response.body).not_to include("Espace annulé")
      expect(response.body).not_to include("Annulée Séjour")
      expect(response.body).to include("Aucune facture en attente")
    end

    it "garde dans la file un séjour vivant et sa demande de facture" do
      stay(invoice_status: "requested", status: "confirmed", first_name: "Vivante")
      get invoicing_path
      expect(response.body).to include("Vivante Séjour")
    end
  end

  # Historique complet des envois, par année (Michael 2026-09-06) : la
  # facturation existe depuis 2023 sur les réservables importés, l'ancienne
  # « mémoire courte » de 15 lignes la rendait invisible.
  describe "factures envoyées" do
    it "liste les factures déjà envoyées, à part de la file" do
      space_booking(invoice_status: "sent", group: "Déjà facturé")
      get invoicing_path
      expect(response.body).to include("Factures envoyées")
      expect(response.body).to include("Déjà facturé")
    end

    it "montre TOUTE l'année, sans se limiter aux 15 dernières" do
      16.times { |i| space_booking(invoice_status: "sent", group: "Envoi n°#{i + 1} clos") }
      get invoicing_path
      16.times { |i| expect(response.body).to include("Envoi n°#{i + 1} clos") }
    end

    it "range l'historique par année, la plus récente d'abord" do
      booking(invoice_status: "sent", group: "Facture de 2024", from_date: Date.new(2024, 5, 10))
      space_booking(invoice_status: "sent", group: "Facture récente")

      get invoicing_path
      expect(response.body).to include("Facture récente")
      expect(response.body).not_to include("Facture de 2024")
      expect(response.body).to include(invoicing_path(year: 2024))

      get invoicing_path(year: 2024)
      expect(response.body).to include("Facture de 2024")
      expect(response.body).not_to include("Facture récente")
    end

    it "retombe sur l'année la plus récente pour une année inconnue" do
      space_booking(invoice_status: "sent", group: "Facture récente")
      get invoicing_path(year: 1999)
      expect(response.body).to include("Facture récente")
    end

    it "n'affiche pas la section quand rien n'a jamais été envoyé" do
      get invoicing_path
      expect(response.body).not_to include("Factures envoyées")
    end
  end

  describe "réservations sans tarif tranché" do
    it "les signale : impossible de facturer sans montant décidé" do
      booking(invoice_status: "", group: "Tarif à trancher", tier: "non défini")
      get invoicing_path
      expect(response.body).to include("sans tarif défini")
      expect(response.body).to include("Tarif à trancher")
    end

    it "n'affiche pas le bloc quand il n'y a rien à trancher" do
      get invoicing_path
      expect(response.body).not_to include("sans tarif défini")
    end
  end

  describe "PATCH changement de statut" do
    it "marque une facture d'hébergement comme envoyée" do
      b = booking(invoice_status: "requested")
      patch invoicing_status_path(kind: "booking", id: b.id), params: { invoice_status: "sent" }
      expect(response).to redirect_to(invoicing_path)
      expect(b.reload.invoice_status).to eq("sent")
    end

    it "remet une facture d'espace dans la file" do
      sb = space_booking(invoice_status: "sent")
      patch invoicing_status_path(kind: "space_booking", id: sb.id), params: { invoice_status: "requested" }
      expect(sb.reload.invoice_status).to eq("requested")
    end

    # Le `kind` pilote un `constantize` : il ne doit accepter QUE les deux clés
    # connues, jamais une classe arbitraire venue des params.
    it "refuse un type de réservation inconnu" do
      patch invoicing_status_path(kind: "User", id: 1), params: { invoice_status: "sent" }
      expect(response).to redirect_to(invoicing_path)
      expect(flash[:alert]).to include("Type de réservation inconnu")
    end

    it "refuse un statut de facture hors liste" do
      b = booking(invoice_status: "requested")
      patch invoicing_status_path(kind: "booking", id: b.id), params: { invoice_status: "n_importe_quoi" }
      expect(flash[:alert]).to include("invalide")
      expect(b.reload.invoice_status).to eq("requested")
    end
  end

  describe "anciennes vues retirées" do
    it "ne route plus /comptabilite" do
      expect { get "/comptabilite" }.to raise_error(ActionController::RoutingError)
    end

    # `/bookings/search` n'explose PAS en RoutingError : depuis le retrait de la
    # route de collection, l'URL retombe sur `bookings#show` avec id="search",
    # donc un RecordNotFound. L'important est qu'elle ne rende plus la recherche.
    it "ne rend plus la recherche de réservations" do
      expect { get "/bookings/search" }.to raise_error(ActiveRecord::RecordNotFound)
    end
  end

  describe "sous-menu Accueil" do
    it "expose Facturation, Paiements et Clients, et plus Comptabilité" do
      get invoicing_path
      expect(response.body).to include("Facturation")
      expect(response.body).to include(%(href="#{payments_path}"))
      expect(response.body).to include(%(href="#{customers_path}"))
      # Scopé au sous-menu : « Comptabilité » est une section primaire depuis
      # le 2026-08-19, et le mot figure donc dans la barre de toutes les pages.
      sous_menu = Nokogiri::HTML(response.body).at_css("#subnav-home")&.text.to_s
      expect(sous_menu).not_to include("Comptabilité")
    end
  end
end
