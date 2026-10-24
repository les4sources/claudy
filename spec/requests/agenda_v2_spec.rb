require "rails_helper"

# Agenda en rubans de la nouvelle interface (redesign, Michael 2026-10-24) :
# une bande par séjour, de l'après-midi de l'arrivée au matin du départ, le
# jour choisi à droite, la liste des jours sur téléphone. L'ancienne interface
# et la vue Sourciers gardent l'ancien calendrier.
RSpec.describe "Agenda en rubans", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:human) { Human.create!(name: "Malau Hulet", email: "malau@les4sources.be") }
  let(:user) { User.create!(email: "agenda-v2@les4sources.be", password: "password123", human_id: human.id, new_interface: true) }
  let(:lodging) { Lodging.create!(name: "La Chevêche", available_for_bookings: true) }
  let(:romarin) { Room.create!(name: "Romarin", code: "ROM", level: 1) }
  let(:balsamine) { Room.create!(name: "Balsamine", code: "BAL", level: 1) }
  # Un mercredi au milieu du mois : la semaine affichée est connue d'avance.
  let(:month) { Date.new(2026, 10, 1) }

  before do
    LodgingRoom.create!(lodging: lodging, room: romarin)
    LodgingRoom.create!(lodging: lodging, room: balsamine)
    sign_in user
  end

  def stay_in(name:, arrival:, departure:, status: "confirmed", rooms: [romarin], adults: 4)
    customer = Customers::UpsertByEmail.call(email: "#{name.parameterize}@example.com",
                                             attrs: { customer_type: "organization", organization_name: name })
    stay = Stay.create!(customer: customer, source: "manual", status: status,
                        arrival_date: arrival, departure_date: departure)
    booking = Booking.create!(firstname: name, from_date: arrival, to_date: departure, adults: adults,
                              children: 0, babies: 0, status: "confirmed", booking_type: "lodging")
    arrival.upto(departure - 1) { |date| rooms.each { |room| Reservation.create!(booking: booking, room: room, date: date) } }
    StayItem.create!(stay: stay, bookable: booking)
    stay
  end

  def ribbon_for(stay)
    Nokogiri::HTML(response.body).css(".ui-ag-desk [data-stay-id='#{stay.id}']")
  end

  it "pose un séjour de l'après-midi de son arrivée au matin de son départ" do
    # Mercredi 21 → samedi 24 octobre 2026 : semaine du lundi 19.
    stay = stay_in(name: "Famille Dubois", arrival: Date.new(2026, 10, 21), departure: Date.new(2026, 10, 24),
                   status: "pre_confirmed")

    get "/", params: { date: month.iso8601, jour: "2026-10-21" }

    expect(response).to have_http_status(:ok)
    ribbons = ribbon_for(stay)
    expect(ribbons.size).to eq(1)
    # Mercredi après-midi = demi-journée 5 (grille 6), samedi matin inclus = 6 demis.
    expect(ribbons.first["style"]).to include("grid-column: 6 / span 6")
    expect(ribbons.first["class"]).to include("ui-rib-pre")
    expect(ribbons.first["aria-label"]).to include("Famille Dubois", "Pré-confirmé", "du 21 octobre au 24 octobre")
    expect(ribbons.first["data-action"]).to eq("stay-details#open")
  end

  it "saute d'un clic jusqu'à trois mois avant ou après le mois affiché" do
    get "/", params: { date: Date.new(2026, 11, 1).iso8601 }

    jump = Nokogiri::HTML(response.body).css(".ui-ag-jump a")
    expect(jump.map(&:text)).to eq(["Août", "Sept.", "Oct.", "Nov.", "Déc.", "Jan. 27", "Fév. 27"])
    expect(jump.first["href"]).to include("date=2026-08-01")
    expect(jump.last["href"]).to include("date=2027-02-01")
    expect(jump[3]["aria-current"]).to eq("page")
  end

  it "coupe une bande au changement de semaine et range deux séjours qui se suivent sur la même ligne" do
    first = stay_in(name: "Jean Peeters", arrival: Date.new(2026, 10, 24), departure: Date.new(2026, 10, 27))
    second = stay_in(name: "Camille Leroy", arrival: Date.new(2026, 10, 27), departure: Date.new(2026, 10, 29))

    get "/", params: { date: month.iso8601 }

    pieces = ribbon_for(first)
    expect(pieces.size).to eq(2)
    expect(pieces.first["class"]).to include("is-cr")
    expect(pieces.last["class"]).to include("is-cl")
    # Le mardi 27 : départ le matin, arrivée l'après-midi, même ligne.
    expect(pieces.last["style"]).to include("grid-column: 1 / span 3", "grid-row: 1")
    expect(ribbon_for(second).first["style"]).to include("grid-column: 4 / span 4", "grid-row: 1")
  end

  it "ouvre le jour choisi dans le panneau : arrivées, départs, cuisine et chambres libres, sans montant" do
    stay_in(name: "Les Scouts de Namur", arrival: Date.new(2026, 10, 24), departure: Date.new(2026, 10, 26), adults: 24)
    leaving = stay_in(name: "Atelier Céramique", arrival: Date.new(2026, 10, 22), departure: Date.new(2026, 10, 24),
                      rooms: [balsamine], adults: 12)
    MealOrder.create!(stay: leaving, kind: "repas", moment: "midi", date: Date.new(2026, 10, 24), people: 12,
                      status: "confirmed", skip_notifications: true)

    get "/", params: { date: month.iso8601, jour: "2026-10-24" }

    panel = Nokogiri::HTML(response.body).at_css("turbo-frame#agenda_day")
    text = panel.text.squish
    expect(text).to include("Samedi 24", "Arrivées", "Les Scouts de Namur", "Départs", "Atelier Céramique")
    expect(text).to match(/Midi\s*12/)
    # Romarin est pris par les Scouts, Balsamine s'est libérée le matin.
    expect(panel.at_css(".ui-ag-free b").text.squish).to eq("Balsamine")
    expect(text).not_to include("€")
  end

  it "montre le veilleur du jour en avatar, les renforts empilés derrière lui" do
    veille = Role.find_or_create_by!(id: OnCall::Resolver::WATCHMAN_ROLE_ID) { |r| r.name = "Veilleur·euse" }
    date = Date.new(2026, 10, 24)
    HumanRole.create!(human: Human.create!(name: "Olivier"), role: veille, date: date, status: "selected")
    HumanRole.create!(human: Human.create!(name: "Steph"), role: veille, date: date, status: "backup")
    HumanRole.create!(human: Human.create!(name: "Lily"), role: veille, date: date, status: "backup")

    get "/", params: { date: month.iso8601, jour: "2026-10-24" }

    watch = Nokogiri::HTML(response.body).at_css("turbo-frame#agenda_day .ui-ag-watch")
    expect(watch["aria-label"]).to eq("Veille : Olivier · en renfort : Steph et Lily")
    expect(watch.css(".ui-ag-backup").size).to eq(2)
    # Le veilleur en dernier : il passe devant les renforts.
    expect(watch.element_children.last["class"]).not_to include("ui-ag-backup")
  end

  it "pose sous chaque jour ses notes et, à côté de la date, qui veille" do
    veille = Role.find_or_create_by!(id: OnCall::Resolver::WATCHMAN_ROLE_ID) { |r| r.name = "Veilleur·euse" }
    HumanRole.create!(human: Human.create!(name: "Steph"), role: veille, date: Date.new(2026, 10, 21), status: "selected")
    Note.create!(date: Date.new(2026, 10, 21), color: "pink", body: "Matin : bain d’ânes pour un groupe de plaines")

    get "/", params: { date: month.iso8601 }

    doc = Nokogiri::HTML(response.body)
    note = doc.at_css(".ui-ag-desk .ui-ag-notes")
    # Mercredi 21 : troisième jour de la semaine, demi-journées 5 et 6.
    expect(note["style"]).to include("grid-column: 5 / span 2")
    expect(note.at_css(".ui-postit-pink").text.squish).to eq("Matin : bain d’ânes pour un groupe de plaines")
    day = doc.css(".ui-ag-desk .ui-ag-day").find { |link| link["aria-label"] == "Mercredi 21 octobre" }
    expect(day.at_css(".ui-ag-day-w")["title"]).to eq("Veille : Steph")
  end

  it "montre les événements et les repas sans séjour, filtrables par sorte" do
    category = EventCategory.create!(name: "Convivialité")
    Event.create!(name: "Pizza Party", starts_at: Time.zone.local(2026, 10, 24, 19), ends_at: Time.zone.local(2026, 10, 24, 23),
                  event_category: category)
    MealOrder.create!(contact_label: "B. Lambert", kind: "repas", moment: "midi", date: Date.new(2026, 10, 31),
                      people: 12, status: "confirmed", skip_notifications: true)

    get "/", params: { date: month.iso8601 }

    doc = Nokogiri::HTML(response.body)
    expect(doc.at_css(".ui-rib-event[data-kind='activity']").text).to include("Pizza Party", "19:00")
    expect(doc.at_css(".ui-rib-meal[data-kind='meal']").text).to include("B. Lambert", "midi, 12")
    expect(doc.css("button.ui-chip").map { |b| b["data-kind"] }).to eq(%w[all lodging room activity meal])
  end

  it "liste sur téléphone les sept jours à partir du jour choisi" do
    stay_in(name: "Chorale du Bocq", arrival: Date.new(2026, 10, 28), departure: Date.new(2026, 10, 29))

    get "/", params: { jour: "2026-10-26" }

    mobile = Nokogiri::HTML(response.body).at_css(".ui-ag-mob")
    headings = mobile.css(".ui-ag-lday-h").map(&:text)
    expect(headings.size).to eq(7)
    expect(headings.first).to include("lundi 26")
    expect(mobile.text.squish).to include("Chorale du Bocq", "Arrivée", "Départ")
    expect(mobile.at_css(".ui-ag-wd.is-sel").text).to include("26")
  end

  it "garde l'ancien calendrier pour la vue Sourciers et pour l'ancienne interface" do
    get "/", params: { view: "organisation" }
    expect(response.body).not_to include("ui-ag-desk")

    user.update!(new_interface: false)
    get "/"
    expect(response.body).not_to include("ui-ag-desk")
  end
end
