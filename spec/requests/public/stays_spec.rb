require "rails_helper"

RSpec.describe "Public::Stays (/sejour/:token)", type: :request do
  let(:customer) { Customer.create!(email: "stay@example.com", customer_type: "individual") }

  let(:booking) do
    Booking.create!(firstname: "Alex", lastname: "Durand", from_date: Date.today + 10,
                    to_date: Date.today + 12, adults: 2, status: "pending",
                    booking_type: "lodging", price_cents: 48_500)
  end

  # `pre_confirmed`, et non plus `pending` : depuis l'inversion de l'ordre
  # (issue #215) un séjour ne doit d'argent qu'à partir de la PRÉ-CONFIRMATION
  # du Pôle Accueil. Une demande encore `pending` n'affiche ni solde ni CTA de
  # paiement — c'est le sujet du bloc « demande en attente » plus bas ; ces
  # exemples-ci portent sur l'affichage des paiements, qui suppose une demande
  # déjà acceptée.
  let(:stay) do
    s = Stay.create!(customer: customer, status: "pre_confirmed", total_amount_cents: 48_500,
                     arrival_date: Date.today + 10, departure_date: Date.today + 12)
    s.stay_items.create!(bookable: booking)
    s
  end

  # Demande DÉPOSÉE, pas encore regardée : la page annonçait « En attente de
  # paiement » et « Payer le solde de 485 € » alors que rien n'est dû avant la
  # pré-confirmation. Qui payait là réglait un séjour qui n'existait pas.
  let(:pending_stay) do
    s = Stay.create!(customer: customer, status: "pending", total_amount_cents: 48_500,
                     arrival_date: Date.today + 30, departure_date: Date.today + 32)
    s.stay_items.create!(bookable: Booking.create!(firstname: "Alex", lastname: "Durand",
                                                   from_date: Date.today + 30, to_date: Date.today + 32,
                                                   adults: 2, status: "pending",
                                                   booking_type: "lodging", price_cents: 48_500))
    s
  end

  describe "GET /sejour/:token — demande EN ATTENTE (issue #215)" do
    before { get "/sejour/#{pending_stay.token}" }

    it "ne réclame aucun paiement" do
      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include('data-stay-balance-cta="true"')
      expect(response.body).not_to include('data-stay-balance="true"')
      expect(response.body).not_to include(I18n.t("public.stays.payment_status.pending"))
    end

    it "explique que la pré-confirmation viendra par email" do
      expect(response.body).to include('data-stay-awaiting-review="true"')
      # La phrase porte des apostrophes : elle arrive échappée dans le HTML.
      expect(response.body).to include(ERB::Util.html_escape(I18n.t("public.stays.payments.awaiting_review")))
    end

    # Le client a le droit de savoir ce qu'il a demandé — ne rien réclamer
    # n'est pas la même chose que ne rien montrer.
    it "affiche quand même le total du séjour" do
      expect(response.body).to include(I18n.t("public.stays.show.total"))
    end
  end

  describe "GET /sejour/:token" do
    it "rend la page sans authentification Devise" do
      get "/sejour/#{stay.token}"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Votre séjour aux 4 Sources")
      expect(response.body).to include("data-stay-items")
    end

    it "affiche le statut de paiement du séjour" do
      get "/sejour/#{stay.token}"
      expect(response.body).to include("En attente de paiement")

      Payment.create!(booking: booking, stay: stay, amount_cents: 48_500, status: "paid", payment_method: "card")
      stay.set_payment_status

      get "/sejour/#{stay.token}"
      expect(response.body).to include("Payé")
    end

    it "expose le CTA de paiement Stripe pour chaque paiement en attente" do
      payment = Payment.create!(booking: booking, stay: stay, amount_cents: 48_500,
                                status: "pending", payment_method: "card")

      get "/sejour/#{stay.token}"

      expect(response.body).to include('data-stay-payments="pending"')
      expect(response.body).to include(pay_public_payment_path(payment))
    end

    it "liste les paiements reçus" do
      Payment.create!(booking: booking, stay: stay, amount_cents: 48_500, status: "paid", payment_method: "card")

      get "/sejour/#{stay.token}"

      expect(response.body).to include('data-stay-payments="paid"')
    end

    it "renvoie 404 sur un token inconnu" do
      get "/sejour/inconnu"
      expect(response).to have_http_status(:not_found)
    end

    it "affiche la note PUBLIQUE du séjour et JAMAIS la note interne" do
      stay.update!(notes: "SECRET INTERNE À NE PAS DIVULGUER")
      stay.public_notes = "<div>Bon séjour à vous et à bientôt</div>"
      stay.save!

      get "/sejour/#{stay.token}"

      expect(response.body).to include("Bon séjour à vous et à bientôt")
      expect(response.body).not_to include("SECRET INTERNE")
    end
  end

  # Epic #55, Phase 3 — ventilation exigible + bouton « Payer le solde ».
  describe "solde exigible (/sejour/:token)" do
    it "affiche le bouton « Payer le solde » quand l'exigible > 0 et aucun paiement en attente" do
      get "/sejour/#{stay.token}"

      expect(response.body).to include('data-stay-balance="true"')
      expect(response.body).to include('data-stay-balance-cta="true"')
      expect(response.body).to include(public_stay_balance_payment_path(stay.token))
    end

    it "masque le bouton quand l'exigible est nul (séjour soldé)" do
      Payment.create!(booking: booking, stay: stay, amount_cents: 48_500, status: "paid", payment_method: "card")

      get "/sejour/#{stay.token}"

      expect(response.body).not_to include('data-stay-balance-cta="true"')
    end

    it "masque le bouton quand un paiement est déjà en attente (l'acompte a son propre CTA)" do
      Payment.create!(booking: booking, stay: stay, amount_cents: 24_250, status: "pending", payment_method: "card")

      get "/sejour/#{stay.token}"

      expect(response.body).not_to include('data-stay-balance-cta="true"')
      # Le CTA générique de l'acompte, lui, reste présent.
      expect(response.body).to include('data-stay-payments="pending"')
    end

    it "distingue les activités validées (exigibles) des activités en attente (non exigibles)" do
      experience = Experience.create!(name: "Sauna", fixed_price_cents: 3_000, price_cents: 0)
      availability = ExperienceAvailability.create!(experience: experience, available_on: Date.today + 11, starts_at: "18:00")
      ExperienceBooking.create!(experience_availability: availability, stay: stay, participants: 2, status: "confirmed")
      ExperienceBooking.create!(experience_availability: availability, stay: stay, participants: 2, status: "pending")
      stay.recompute_aggregates!

      get "/sejour/#{stay.token}"

      expect(response.body).to include('data-balance-pending="true"')
      expect(response.body).to include(I18n.t("public.stays.balance.experiences_confirmed"))
    end
  end

  # Issue #79 — le funnel public persiste camping/van/repas : la page /sejour doit
  # les afficher en lignes distinctes (repas inclus, bien que non `stay_items`) et
  # rester cohérente (décomposition qui somme au total).
  describe "GET /sejour/:token — composition camping + repas (issue #79)" do
    it "affiche les lignes camping et repas" do
      camping = CampingBooking.create!(firstname: "Alex", from_date: Date.today + 10,
                                       to_date: Date.today + 12, people: 3, status: "pending",
                                       kind: "tente", price_cents: 4_500)
      stay.stay_items.create!(bookable: camping)
      stay.meal_orders.create!(kind: "buffet_vege", people: 4, price_cents: 4_800) # sans date
      stay.update!(total_amount_cents: 48_500 + 4_500 + 4_800)

      get "/sejour/#{stay.token}"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(I18n.t("public.stays.items.camping"))
      expect(response.body).to include(I18n.t("public.stays.items.meal"))
    end
  end
end

# Fourre-tout OTA (2026-07-20) : un client fourre-tout (générique ou par OTA)
# ne doit JAMAIS voir d'autres séjours sur la page publique d'un séjour — les
# clients standards, eux, verront à terme leur historique.
RSpec.describe "Public /sejour/:token — anti-fuite fourre-tout", type: :request do
  it "la page d'un séjour d'un client fourre-tout OTA ne mentionne aucun autre séjour" do
    airbnb = Customer.create!(email: Customer::OTA_CATCH_ALL_EMAILS.fetch("airbnb"),
                              first_name: "Client", last_name: "Airbnb", customer_type: "organization", organization_name: "Airbnb")
    expect(airbnb.catch_all?).to be(true)

    stay_a = Stay.create!(customer: airbnb, source: "manual", status: "confirmed",
                          arrival_date: Date.today + 10, departure_date: Date.today + 12)
    stay_b = Stay.create!(customer: airbnb, source: "manual", status: "confirmed",
                          arrival_date: Date.today + 20, departure_date: Date.today + 22)

    get "/sejour/#{stay_a.token}"

    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include(stay_b.token)
    expect(response.body).not_to include("##{stay_b.id}")
  end
end
