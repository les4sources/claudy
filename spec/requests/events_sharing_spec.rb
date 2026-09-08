require "rails_helper"

# Epic #245, phase 1 — organisateurs, pôle, taux et frais fixes.
RSpec.describe "Événements — partage et frais fixes", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user) { User.create!(email: "admin-events@les4sources.be", password: "password123") }
  let!(:category) { EventCategory.create!(name: "Formation") }
  let!(:seb) { Human.create!(name: "Sébastien") }
  let!(:magali) { Human.create!(name: "Magali") }
  let!(:team) { Team.create!(name: "Transmission") }
  let(:turbo) { { "Accept" => "text/vnd.turbo-stream.html" } }

  before { sign_in user }

  # `Event` valide ses attributs virtuels `starts_at_date` / `ends_at_date` :
  # ils sont obligatoires même quand on écrit `starts_at` directement.
  def create_event(**attrs)
    Event.create!({ name: "Stage low-tech", event_category: category,
                    starts_at: 1.week.from_now, ends_at: 1.week.from_now + 2.days,
                    starts_at_date: 1.week.from_now.to_date,
                    ends_at_date: (1.week.from_now + 2.days).to_date }.merge(attrs))
  end

  def event_params(overrides = {})
    { event: { name: "Stage low-tech", event_category_id: category.id,
               starts_at_date: Date.current.to_s, ends_at_date: (Date.current + 2).to_s }.merge(overrides) }
  end

  describe "le taux" do
    it "vaut 70 % par défaut" do
      expect(create_event.effective_organizer_share_percent).to eq(70)
    end

    it "suit la clé `event.organizer_share` de Paramètres > Tarifs" do
      Rate.create!(key: "event.organizer_share", amount_cents: 60, unit: "percent", label: "Part")
      Pricing::Rates.reset!

      expect(create_event.effective_organizer_share_percent).to eq(60)
      Pricing::Rates.reset!
    end

    it "est surchargé par le taux de l'événement" do
      event = create_event(organizer_share_percent: 100)

      expect(event.effective_organizer_share_percent).to eq(100)
      expect(event).to be_organizer_share_overridden
    end

    it "refuse un taux hors 0–100" do
      expect { create_event(organizer_share_percent: 120) }.to raise_error(ActiveRecord::RecordInvalid)
    end

    it "expose la clé dans un groupe « Événements » de Paramètres > Tarifs" do
      Rates::SeedFromCatalog.new.run

      get rates_path

      expect(response.body).to include("Événements")
      expect(response.body).to include("event.organizer_share")
      rate = Rate.find_by(key: "event.organizer_share")
      expect(rate.amount_cents).to eq(70)
      expect(rate.unit).to eq("percent")
    end
  end

  describe "les organisateurs" do
    it "s'enregistrent depuis le formulaire, avec leur poids" do
      post events_path, params: event_params(
        team_id: team.id, organizer_share_percent: 80,
        organizers: { seb.id.to_s => { selected: "1", weight: "2" },
                      magali.id.to_s => { selected: "1", weight: "1" } }
      )

      event = Event.find_by(name: "Stage low-tech")
      expect(event.team).to eq(team)
      expect(event.organizer_share_percent).to eq(80)
      expect(event.event_organizers.pluck(:human_id, :weight)).to contain_exactly([seb.id, 2], [magali.id, 1])
    end

    it "retire celui qu'on décoche et garde la ligne de celui qui reste" do
      event = create_event
      ligne = EventOrganizer.create!(event: event, human: seb, weight: 3)
      EventOrganizer.create!(event: event, human: magali, weight: 1)

      patch event_path(event), params: event_params(
        organizers: { seb.id.to_s => { selected: "1", weight: "3" },
                      magali.id.to_s => { selected: "0", weight: "1" } }
      )

      expect(event.reload.event_organizers.pluck(:human_id)).to eq([seb.id])
      expect(EventOrganizer.find_by(id: ligne.id)).to be_present
    end

    it "ramène un poids nul ou absent à 1 — personne ne disparaît en silence" do
      post events_path, params: event_params(
        organizers: { seb.id.to_s => { selected: "1", weight: "0" } }
      )

      expect(Event.find_by(name: "Stage low-tech").event_organizers.first.weight).to eq(1)
    end

    it "prévient qu'aucune répartition n'est possible sans organisateur" do
      event = create_event

      get event_path(event, tab: "comptabilite")

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Aucune répartition possible")
    end

    it "montre la part de chacun au prorata des poids" do
      event = create_event
      EventOrganizer.create!(event: event, human: seb, weight: 3)
      EventOrganizer.create!(event: event, human: magali, weight: 1)

      get event_path(event, tab: "comptabilite")

      expect(response.body).to include("poids 3")
      expect(response.body).to include("75 %")
      expect(response.body).to include("25 %")
    end
  end

  describe "les frais fixes" do
    let!(:event) { create_event }

    it "s'ajoutent et renvoient le bloc en Turbo Stream" do
      expect {
        post event_costs_path(event),
             params: { event_cost: { label: "Matériel", amount: "125,50" } }, headers: turbo
      }.to change(EventCost, :count).by(1)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("event-costs")
      expect(EventCost.last.amount_cents).to eq(12_550)
      expect(EventCost.last.kind).to eq("other")
    end

    it "refusent une ligne sans libellé" do
      expect {
        post event_costs_path(event), params: { event_cost: { label: "", amount: "10" } }, headers: turbo
      }.not_to change(EventCost, :count)

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "se modifient" do
      cost = EventCost.create!(event: event, label: "Matériel", amount_cents: 10_000)

      patch event_cost_path(event, cost),
            params: { event_cost: { label: "Matériel loué", amount: "80" } }, headers: turbo

      expect(cost.reload.label).to eq("Matériel loué")
      expect(cost.amount_cents).to eq(8_000)
    end

    it "se retirent en douceur" do
      cost = EventCost.create!(event: event, label: "Matériel", amount_cents: 10_000)

      delete event_cost_path(event, cost), headers: turbo

      expect(EventCost.count).to eq(0)
      expect(EventCost.with_deleted { EventCost.count }).to eq(1)
    end

    it "totalisent ce qui se déduira de la recette" do
      EventCost.create!(event: event, label: "Matériel", amount_cents: 10_000)
      EventCost.create!(event: event, label: "Intervenant", amount_cents: 5_000)

      expect(event.reload.fixed_costs_cents).to eq(15_000)
    end
  end

  describe "la reprise d'une réservation d'espace" do
    let!(:event) { create_event }
    let!(:space) { Space.create!(name: "Grande Salle", capacity: 50) }
    let!(:booking) do
      sb = SpaceBooking.create!(firstname: "Stage", from_date: Date.current, to_date: Date.current,
                                status: "confirmed", price_cents: 29_000, event: event)
      sb.space_reservations.create!(space: space, date: Date.current, duration: "day")
      sb
    end

    it "est proposée tant qu'elle n'est pas passée en frais" do
      get event_path(event, tab: "comptabilite")

      expect(response.body).to include("Ajouter en frais")
      expect(response.body).to include("Grande Salle")
      expect(response.body).to include("290,00 €")
    end

    it "crée la ligne avec le prix PERSISTÉ et garde le lien vers la réservation" do
      post from_space_booking_event_costs_path(event, space_booking_id: booking.id), headers: turbo

      cost = EventCost.last
      expect(cost.amount_cents).to eq(29_000)
      expect(cost.kind).to eq("space")
      expect(cost.source).to eq(booking)
      expect(cost.label).to include("Grande Salle")
    end

    it "ne se propose plus une fois reprise — pas de double compte" do
      post from_space_booking_event_costs_path(event, space_booking_id: booking.id), headers: turbo

      expect(event.reload.space_bookings_not_yet_costed).to be_empty
    end
  end

  describe "les onglets" do
    it "affiche les informations par défaut" do
      event = create_event

      get event_path(event)

      expect(response.body).to include("Comptabilité")
      expect(response.body).to include("Nombre de participants")
    end
  end
end
