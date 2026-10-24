require "rails_helper"

# Nouvelle interface (redesign, Michael 2026-10-24) : l'interrupteur par
# personne, la coquille (barre latérale, onglets) et l'écran « Aujourd'hui »
# sur de vraies données. L'ancienne interface reste celle par défaut.
RSpec.describe "Nouvelle interface et écran Aujourd'hui", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:human) { Human.create!(name: "Malau Hulet", email: "malau@les4sources.be") }
  let(:user) { User.create!(email: "accueil-v2@les4sources.be", password: "password123", human_id: human.id) }
  let(:room) { Room.create!(name: "Chambre B", code: "CHB", level: 1) }
  let(:today) { Date.current }

  before { sign_in user }

  def stay_with_room(name:, arrival:, departure:, status: "confirmed", adults: 4)
    customer = Customers::UpsertByEmail.call(email: "#{name.parameterize}@example.com",
                                             attrs: { customer_type: "organization", organization_name: name })
    stay = Stay.create!(customer: customer, source: "manual", status: status,
                        arrival_date: arrival, departure_date: departure)
    booking = Booking.create!(firstname: name, from_date: arrival, to_date: departure,
                              adults: adults, children: 0, babies: 0,
                              status: "confirmed", booking_type: "lodging")
    arrival.upto(departure - 1) { |date| Reservation.create!(booking: booking, room: room, date: date) }
    StayItem.create!(stay: stay, bookable: booking)
    stay
  end

  describe "interrupteur" do
    it "garde l'ancienne interface par défaut" do
      get "/"

      expect(response.body).not_to include("ui-side")
      expect(response.body).to include("Essayer la nouvelle interface")
    end

    it "bascule dans la nouvelle interface, puis revient d'un clic" do
      patch "/interface", params: { new_interface: true }

      expect(user.reload.new_interface).to be(true)
      expect(response).to redirect_to("/aujourdhui")

      get "/"
      expect(response.body).to include('class="ui-side"')
      expect(response.body).to include("ui-tabbar")
      expect(response.body).to include("Revenir à l’ancienne interface")
      expect(response.body).not_to include("Essayer la nouvelle interface")

      patch "/interface", params: { new_interface: false }
      expect(user.reload.new_interface).to be(false)
    end

    it "arrive déjà repliée quand le navigateur l'a choisi, avec une infobulle par entrée" do
      user.update!(new_interface: true)
      cookies[:ui_side] = "collapsed"

      get "/aujourdhui"

      expect(response.body).to match(/<body[^>]*class="[^"]*ui-side-collapsed/)
      expect(response.body).to include('data-tip="Aujourd’hui"')
      expect(response.body).to include('data-tip="Déplier la barre"')
    end

    it "marque l'écran courant dans la barre latérale" do
      user.update!(new_interface: true)

      get "/aujourdhui"

      expect(response.body).to match(%r{<a aria-current="page" href="/aujourdhui">})
    end
  end

  describe "Aujourd'hui" do
    it "dit la journée : arrivées, départs, couverts du soir, sans aucun montant" do
      arriving = stay_with_room(name: "Les Scouts de Namur", arrival: today, departure: today + 2, adults: 24)
      stay_with_room(name: "Atelier Céramique", arrival: today - 2, departure: today, adults: 12)
      MealOrder.create!(stay: arriving, kind: "repas", moment: "soir", date: today, people: 24,
                        status: "requested", skip_notifications: true)

      get "/aujourdhui"

      expect(response).to have_http_status(:ok)
      body = response.body
      expect(body).to include("Bonjour Malau.")
      expect(body).to include('<mark class="ui-hl">24 couverts</mark>')
      expect(body).to include("La cuisine n’a pas encore répondu pour Les Scouts de Namur.")
      expect(body).to include("Les Scouts de Namur")
      expect(body).to include("Atelier Céramique")
      expect(body).to include("Arrivée")
      expect(body).to include("Départ")
      expect(body).to include("À valider")
      expect(body).not_to match(/\d\s?€/)
    end

    it "ouvre un séjour dans la modale du calendrier" do
      stay = stay_with_room(name: "Famille Dubois", arrival: today, departure: today + 3, status: "pre_confirmed")

      get "/aujourdhui"

      expect(response.body).to include(%(data-action="stay-details#open" href="/stays/#{stay.id}"))
      expect(response.body).to include("Pré-confirmé")
      expect(response.body).to include("3 nuits")
    end

    it "liste ce qui attend une réponse, avec le lien vers l'écran où l'on répond" do
      stay_with_room(name: "Chorale du Bocq", arrival: today + 5, departure: today + 6, status: "pending")

      get "/aujourdhui"

      expect(response.body).to include("1 demande de séjour sans réponse")
      expect(response.body).to include("/stays?status=pending")
    end

    it "parle d'une journée calme quand personne n'arrive ni ne part" do
      get "/aujourdhui"

      expect(response.body).to include("Journée calme")
    end

    it "condense le tableau de bord dans « Pour toi » : cuisine à trancher, notifications, prochains rôles" do
      chorale = stay_with_room(name: "Chorale du Bocq", arrival: today + 4, departure: today + 5)
      MealOrder.create!(stay: chorale, kind: "gouter", moment: "gouter", date: today + 4, people: 18,
                        status: "requested", responsible_human: human, skip_notifications: true)
      Notification.create!(recipient: user, kind: "comment", title: "Olivier a commenté le séjour", url: "/stays")
      HumanRole.create!(human: human, role: Role.create!(name: "Veille de nuit"), date: today + 1, status: "selected")
      olivier = Human.create!(name: "Olivier", email: "olivier@les4sources.be")
      cycle = Cycle.create!(name: "Cycle d'automne", start_date: today - 7, end_date: today + 30)
      CycleAction.create!(human: olivier, cycle: cycle, label: "Relire le contrat", category: :deleguee, delegate_to_human: human)

      get "/aujourdhui"

      body = response.body
      expect(body).to include("Pour toi")
      expect(body).to include("la cuisine attend ta réponse")
      expect(body).to include("Ok !")
      expect(body).to include("Olivier a commenté le séjour")
      expect(body).to include("Toi, demain")
      expect(body).to include("confiée par Olivier")
      expect(body).not_to match(/\d\s?€/)
    end

    it "s'ouvre au rôle Kid (agenda en lecture) sans la file « À traiter »" do
      kid = User.create!(email: "kid-v2@les4sources.be", password: "password123", access_roles: %w[kid], new_interface: true)
      stay_with_room(name: "Chorale du Bocq", arrival: today + 5, departure: today + 6, status: "pending")
      sign_in kid

      get "/aujourdhui"

      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include("À traiter")
      expect(response.body).not_to include("Nouveau séjour")
    end
  end
end
