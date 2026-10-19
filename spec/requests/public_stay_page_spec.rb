require "rails_helper"

# Refonte de la page client du séjour (Michael, 2026-08-20). Elle est devenue la
# destination de l'email de confirmation : elle doit montrer la composition, les
# activités, les paiements, la boulangerie et les AUTRES séjours du client — sans
# jamais fuiter l'historique d'un client fourre-tout.
RSpec.describe "Public /sejour/:token — page client enrichie", type: :request do
  let(:customer) { Customer.create!(email: "fidele@example.com", first_name: "Léa") }
  let(:lodging)  { Lodging.create!(name: "La Hulotte", price_night_cents: 48_500) }

  def build_stay(status: "confirmed", arrival: Date.today + 10, departure: Date.today + 12, customer: nil)
    booking = Booking.create!(firstname: "Léa", lastname: "Martin", lodging: lodging,
                              from_date: arrival, to_date: departure, adults: 2, children: 1,
                              status: status, booking_type: "lodging", price_cents: 48_500)
    stay = Stay.create!(customer: customer || self.customer, source: "manual", status: status,
                        arrival_date: arrival, departure_date: departure,
                        total_amount_cents: 48_500)
    stay.stay_items.create!(bookable: booking)
    stay
  end

  it "ne laisse échapper aucune traduction manquante" do
    get "/sejour/#{build_stay.token}"

    expect(response.body).not_to include("translation missing")
  end

  it "annonce clairement que le séjour est confirmé" do
    get "/sejour/#{build_stay.token}"

    expect(response.body).to include('data-stay-hero="true"')
    expect(response.body).to include(I18n.t("public.stays.show.confirmed_pill"))
  end

  # Séjour ANNULÉ (2026-09-05) : la page le dit sans détour et ne propose plus
  # de payer un solde — ni par le bouton, ni par un POST direct.
  it "annonce l'annulation et n'offre plus le paiement du solde" do
    stay = build_stay(status: "canceled")

    get "/sejour/#{stay.token}"

    expect(response).to have_http_status(:ok)
    expect(response.body).to include('data-stay-canceled="true"')
    expect(response.body).to include(I18n.t("public.stays.show.canceled_pill"))
    expect(response.body).to include(ERB::Util.html_escape(I18n.t("public.stays.show.canceled_intro")))
    # Plus de « reste dû » ni de badge de paiement : il n'y a plus rien à payer.
    expect(response.body).not_to include('data-balance-due="true"')
    expect(response.body).not_to include(I18n.t("public.stays.payment_status.pending"))
    expect(response.body).not_to include(new_public_stay_change_request_path(stay.token))
    expect(response.body).not_to include(I18n.t("public.stays.show.confirmed_pill"))
    expect(response.body).not_to include('data-stay-balance-cta="true"')
    expect(response.body).not_to include("translation missing")
  end

  it "refuse le paiement du solde d'un séjour annulé" do
    stay = build_stay(status: "canceled")

    expect { post "/sejour/#{stay.token}/payer-le-solde" }.not_to change(Payment, :count)

    expect(response).to redirect_to("/sejour/#{stay.token}")
    expect(flash[:alert]).to include("annulé")
  end

  it "détaille la composition avec son total" do
    get "/sejour/#{build_stay.token}"

    expect(response.body).to include('data-stay-items="true"')
    expect(response.body).to include("La Hulotte")
    expect(response.body).to include('data-stay-total="true"')
    expect(response.body).to include(I18n.t("public.stays.show.vat_notice"))
  end

  # Le total inclut les activités : il doit donc être affiché APRÈS elles, sinon
  # il additionne des lignes que la carte au-dessus de lui ne montre pas.
  it "place le total après les activités, pas au pied de la seule composition" do
    stay = build_stay
    experience = Experience.create!(name: "Poterie", fixed_price_cents: 3_000, price_cents: 0)
    availability = ExperienceAvailability.create!(experience: experience, available_on: Date.today + 11, starts_at: "10:00")
    ExperienceBooking.create!(experience_availability: availability, stay: stay, participants: 2, status: "confirmed")
    stay.recompute_aggregates!

    get "/sejour/#{stay.token}"

    expect(response.body.index('data-stay-total="true"'))
      .to be > response.body.index('data-stay-activities="true"')
  end

  # La page se contredisait : « Aucun paiement n'est attendu » sous un bouton
  # « Payer le solde ».
  it "ne dit pas « aucun paiement attendu » quand un solde est réclamé" do
    get "/sejour/#{build_stay.token}"

    expect(response.body).to include('data-stay-balance-cta="true"')
    expect(response.body).not_to include(I18n.t("public.stays.show.no_payment"))
  end

  # Les activités n'étaient visibles QUE par leur montant, dans la ventilation
  # du solde — jamais par leur nom.
  it "nomme les activités du séjour, et marque celles qui restent à confirmer" do
    stay = build_stay
    experience = Experience.create!(name: "Balade avec les ânes", fixed_price_cents: 3_000, price_cents: 0)
    availability = ExperienceAvailability.create!(experience: experience, available_on: Date.today + 11, starts_at: "10:00")
    ExperienceBooking.create!(experience_availability: availability, stay: stay, participants: 3, status: "confirmed")

    other = Experience.create!(name: "Atelier forge", fixed_price_cents: 4_000, price_cents: 0)
    other_slot = ExperienceAvailability.create!(experience: other, available_on: Date.today + 11, starts_at: "14:00")
    ExperienceBooking.create!(experience_availability: other_slot, stay: stay, participants: 2, status: "pending")
    stay.recompute_aggregates!

    get "/sejour/#{stay.token}"

    expect(response.body).to include('data-stay-activities="true"')
    expect(response.body).to include("Balade avec les ânes")
    expect(response.body).to include("Atelier forge")
    expect(response.body).to include(I18n.t("public.stays.show.activity_pending"))
  end

  # Le séjour #1518 (Michael, 2026-10-19) : la Pizza Party rattachée comptait
  # dans le total sans apparaître nulle part sur la page.
  it "montre la Pizza Party rattachée dans la composition et dans la ventilation" do
    stay = build_stay
    PartyReservation.create!(stay: stay, source: "tranchesdevie", external_id: 18, held_on: Date.today + 10,
                             slot: "soir", persons: 20, price_cents: 14_000, status: "active")
    PartyReservation.create!(stay: stay, source: "tranchesdevie", external_id: 19, persons: 8,
                             price_cents: 9_000, status: "refunded")
    stay.recompute_aggregates!

    get "/sejour/#{stay.token}"

    items = response.body[/data-stay-items="true".*?<\/ul>/m]
    expect(items).to include("Pizza Party · 20 pers.", "soir", "140")
    expect(items).not_to include("8 pers.")
    expect(response.body).to include('data-balance-party="true"')
    lodging_line = response.body[/#{I18n.t("public.stays.balance.lodging_and_spaces").gsub("&", "&amp;")}.*?<\/dd>/m]
    expect(lodging_line).to include("485")
  end

  it "renvoie vers Tranches de Vie pour le pain et la Pizza Party" do
    get "/sejour/#{build_stay.token}"

    expect(response.body).to include('data-stay-bakery="true"')
    expect(response.body).to include("https://tranchesdevie.les4sources.be")
    expect(response.body).to include("Pizza Party")
  end

  describe "les autres séjours du client" do
    it "liste les autres séjours CONFIRMÉS, à venir et passés" do
      current  = build_stay
      upcoming = build_stay(arrival: Date.today + 40, departure: Date.today + 42)
      past     = build_stay(arrival: Date.today - 40, departure: Date.today - 38)

      get "/sejour/#{current.token}"

      expect(response.body).to include('data-stay-siblings="true"')
      expect(response.body).to include(public_stay_path(upcoming.token))
      expect(response.body).to include(public_stay_path(past.token))
      # Le séjour courant ne se liste pas lui-même. On vise le href EXACT : son
      # jeton apparaît par ailleurs dans les URL « payer le solde » et
      # « modification », qui sont d'autres chemins.
      expect(response.body).not_to include(%(href="#{public_stay_path(current.token)}"))
    end

    it "ignore les séjours encore en attente — une demande n'est pas un séjour acquis" do
      current = build_stay
      en_attente = build_stay(status: "pending", arrival: Date.today + 40, departure: Date.today + 42)

      get "/sejour/#{current.token}"

      expect(response.body).not_to include(public_stay_path(en_attente.token))
    end

    it "n'affiche aucune section quand le client n'a qu'un seul séjour" do
      get "/sejour/#{build_stay.token}"

      expect(response.body).not_to include('data-stay-siblings="true"')
    end
  end

  # Séjour #1554 (Michael, 2026-10-19) : une activité seule pour une
  # organisation, sans hébergement ni espace. « Vos informations » restait vide.
  it "montre le nom et les coordonnées du client d'un séjour sans réservable" do
    org = Customer.create!(customer_type: "organization", organization_name: "Fondation Rurale de Wallonie",
                           email: "contact@frw.be", phone: "+32 81 26 18 82")
    stay = Stay.create!(customer: org, source: "manual", status: "confirmed",
                        arrival_date: Date.today + 10, departure_date: Date.today + 10)

    get "/sejour/#{stay.token}"

    contact = response.body[/data-stay-contact="true".*?<\/dd>/m]
    expect(contact).to include("Fondation Rurale de Wallonie")
    expect(contact).to include("contact@frw.be")
    expect(contact).to include("+3281261882")
  end

  # Michael, 2026-10-19 : le numéro à donner aux clients est celui du Pôle
  # Accueil, pas l'ancien +32 455 13 61 42.
  it "donne le numéro du Pôle Accueil pour les questions" do
    get "/sejour/#{build_stay.token}"

    expect(response.body).to include('href="tel:+32490467710"')
    expect(response.body).not_to include("455136142")
  end
end
