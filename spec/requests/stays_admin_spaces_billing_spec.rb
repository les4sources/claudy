require "rails_helper"

# Epic #81, Phase 6 — Facturation ESPACE enrichie dans le séjour. Le canal direct
# `SpaceBookings::CreateService` porte des attributs de facturation (acompte,
# caution, mode de paiement, événement, horaires) que le séjour ignorait. On les
# fait transiter par le `Reservations::Draft` (`space_billing`) et persister sur
# le `SpaceBooking` — à la création ET à l'édition, sans jamais déclencher d'email.
#
# Invariant de survie : une réédition qui NE PORTE PAS la facturation (clé
# `space_billing` absente) conserve les valeurs existantes ; une réédition qui la
# porte l'applique telle quelle (champ vide → nil, jamais 0 forcé).
RSpec.describe "Stays — facturation espaces (epic #81, Phase 6)", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user) { User.create!(email: "admin-space-billing@les4sources.be", password: "password123") }
  before { sign_in user }

  let!(:lodging)      { Lodging.create!(name: "La Hulotte", summary: "gîte") }
  let!(:grande_salle) { Space.create!(name: "Grande Salle", capacity: 1) }
  let(:arrival)       { Date.today + 30 }
  let(:departure)     { Date.today + 32 }

  let!(:event) do
    category = EventCategory.create!(name: "Fête", color: "blue")
    Event.create!(
      name: "Mariage Martin", event_category: category,
      starts_at: arrival.to_time, ends_at: departure.to_time,
      starts_at_date: arrival, ends_at_date: departure
    )
  end

  def base_params(overrides = {})
    {
      stay: {
        customer_mode: "new",
        new_customer: { first_name: "Alice", last_name: "Martin", email: "alice@example.com", phone: "0470111222" },
        arrival_date: arrival.iso8601, departure_date: departure.iso8601,
        adults: 2, children: 0, dogs_count: 0,
        lodging_id: lodging.id, status: "pending"
      }.merge(overrides)
    }
  end

  def hall_param(kind: "grande_salle", date: nil, period: "journee")
    { "0" => { kind: kind, date: (date || arrival).iso8601, period: period } }
  end

  def full_billing(overrides = {})
    {
      advance_amount: "50", deposit_amount: "200",
      payment_method: "bank_transfer", event_id: event.id,
      arrival_time: "14:00", departure_time: "11:00"
    }.merge(overrides)
  end

  def space_booking_of(stay)
    stay.stay_items.where(bookable_type: "SpaceBooking").first.bookable
  end

  # Crée un séjour hébergement + espace facturé, renvoie le Stay rechargé.
  def create_billed_stay(billing: full_billing, halls: hall_param)
    post stays_path, params: base_params(halls: halls, space_billing: billing)
    Stay.order(:created_at).last
  end

  describe "GET /stays/new — sous-panneau facturation espaces" do
    it "rend les champs de facturation espaces (masqués par défaut)" do
      get new_stay_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Facturation espaces")
      expect(response.body).to include('name="stay[space_billing][advance_amount]"')
      expect(response.body).to include('name="stay[space_billing][deposit_amount]"')
      expect(response.body).to include('name="stay[space_billing][payment_method]"')
      expect(response.body).to include('name="stay[space_billing][event_id]"')
      expect(response.body).to include('name="stay[space_billing][arrival_time]"')
      expect(response.body).to include('name="stay[space_billing][departure_time]"')
      # Reprend les valeurs de mode de paiement du form direct.
      expect(response.body).to include('value="bank_transfer"')
    end
  end

  describe "POST /stays — création avec espace facturé" do
    it "persiste acompte, caution, mode, événement et horaires sur le SpaceBooking" do
      stay = create_billed_stay
      expect(response).to redirect_to(recent_stays_path)

      sb = space_booking_of(stay)
      expect(sb.advance_amount_cents).to eq(5_000)   # 50 € → cents, comme le canal direct
      expect(sb.deposit_amount_cents).to eq(20_000)  # 200 €
      expect(sb.payment_method).to eq("bank_transfer")
      expect(sb.event_id).to eq(event.id)
      expect(sb.arrival_time).to eq("14:00")
      expect(sb.departure_time).to eq("11:00")
      # Parité : aucun paiement Stripe, aucun email déclenché.
      expect(stay.payments).to be_empty
      expect(ActionMailer::Base.deliveries).to be_empty
    end

    it "champ vide → nil (jamais 0 forcé) pour les montants, nil pour les autres" do
      stay = create_billed_stay(billing: {
        advance_amount: "", deposit_amount: "",
        payment_method: "", event_id: "", arrival_time: "", departure_time: ""
      })
      sb = space_booking_of(stay)
      expect(sb.advance_amount_cents).to be_nil
      expect(sb.deposit_amount_cents).to be_nil
      expect(sb.payment_method).to be_nil
      expect(sb.event_id).to be_nil
      expect(sb.arrival_time).to be_nil
      expect(sb.departure_time).to be_nil
    end
  end

  describe "GET /stays/:id/edit — préremplissage de la facturation" do
    it "restitue les valeurs de facturation de l'espace existant" do
      stay = create_billed_stay
      get edit_stay_path(stay)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('value="50"')                       # acompte €
      expect(response.body).to include('value="200"')                      # caution €
      expect(response.body).to include('value="14:00"')                    # heure d'arrivée
      expect(response.body).to include('value="11:00"')                    # heure de départ
      # Mode de paiement + événement présélectionnés.
      expect(response.body).to match(/selected="selected" value="bank_transfer"/)
      expect(response.body).to match(/selected="selected" value="#{event.id}"/)
    end
  end

  describe "PATCH /stays/:id — édition de la facturation" do
    def update_params(stay, overrides = {})
      {
        stay: {
          customer_mode: "existing", customer_id: stay.customer_id, new_customer: {},
          arrival_date: arrival.iso8601, departure_date: departure.iso8601,
          adults: 2, children: 0, dogs_count: 0,
          lodging_id: lodging.id, status: "pending",
          halls: hall_param
        }.merge(overrides)
      }
    end

    it "modifie l'acompte et le persiste" do
      stay = create_billed_stay
      patch stay_path(stay), params: update_params(stay, space_billing: full_billing(advance_amount: "80"))
      expect(response).to redirect_to(recent_stays_path)

      sb = space_booking_of(stay.reload)
      expect(sb.advance_amount_cents).to eq(8_000)
      # Le reste de la facturation n'est pas altéré par ce changement.
      expect(sb.deposit_amount_cents).to eq(20_000)
      expect(sb.payment_method).to eq("bank_transfer")
    end

    it "réédition SANS clé space_billing → valeurs de facturation conservées" do
      stay = create_billed_stay
      # Édition qui NE touche PAS la facturation (clé absente du form).
      patch stay_path(stay), params: update_params(stay)
      expect(response).to redirect_to(recent_stays_path)

      sb = space_booking_of(stay.reload)
      expect(sb.advance_amount_cents).to eq(5_000)
      expect(sb.deposit_amount_cents).to eq(20_000)
      expect(sb.payment_method).to eq("bank_transfer")
      expect(sb.event_id).to eq(event.id)
      expect(sb.arrival_time).to eq("14:00")
      expect(sb.departure_time).to eq("11:00")
    end

    it "vider un champ à l'édition le remet à nil (pas 0 forcé)" do
      stay = create_billed_stay
      patch stay_path(stay), params: update_params(stay, space_billing: full_billing(advance_amount: ""))
      expect(response).to redirect_to(recent_stays_path)

      sb = space_booking_of(stay.reload)
      expect(sb.advance_amount_cents).to be_nil
      expect(sb.deposit_amount_cents).to eq(20_000) # les autres inchangés
    end

    it "édition de la facturation ne déclenche aucun email" do
      stay = create_billed_stay
      ActionMailer::Base.deliveries.clear
      patch stay_path(stay), params: update_params(stay, space_billing: full_billing(deposit_amount: "300"))
      expect(response).to redirect_to(recent_stays_path)
      expect(ActionMailer::Base.deliveries).to be_empty
      expect(space_booking_of(stay.reload).deposit_amount_cents).to eq(30_000)
    end
  end
end
