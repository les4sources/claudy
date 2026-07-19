require "rails_helper"

# Epic #81, Phase 7 — Duplication de séjour. Le service NE clone PAS en base :
# il reconstruit un `Reservations::Draft` prérempli depuis le séjour source, prêt
# à alimenter le form NEW. L'admin choisit de NOUVELLES dates puis soumet — c'est
# la création normale (Reservations::Builder) qui écrit en base.
#
# Ce qui est COPIÉ : client, composition (hébergement, espaces + facturation,
# repas…). Ce qui est EXCLU : toutes les dates (séjour + éléments datés), les
# paiements (jamais reconstruits par le draft) et le prix imposé (le devis se
# recalcule ; l'admin le re-saisit au besoin).
RSpec.describe Stays::DuplicateService, type: :service do
  let!(:lodging)      { Lodging.create!(name: "La Hulotte", summary: "gîte") }
  let!(:grande_salle) { Space.create!(name: "Grande Salle", capacity: 1) }
  let(:arrival)       { Date.today + 30 }
  let(:departure)     { Date.today + 32 }

  # Séjour source multi-éléments : hébergement + espace facturé + repas, créé via
  # le Builder admin (aucun paiement, aucun email — parité canal admin).
  def build_source_stay(price_override_cents: nil)
    draft = Reservations::Draft.new(
      lodging_id:     lodging.id,
      arrival_date:   arrival,
      departure_date: departure,
      adults:         2,
      dogs_count:     0,
      first_name:     "Alice",
      last_name:      "Martin",
      email:          "alice@example.com",
      phone:          "0470111222",
      halls:          [{ kind: "grande_salle", date: arrival.iso8601, period: "journee" }],
      meals:          [{ kind: "buffet", date: arrival.iso8601, people: 3 }],
      space_billing:  { advance_amount: "50", deposit_amount: "200", payment_method: "bank_transfer" }
    )
    builder = Reservations::Builder.new(
      draft: draft, admin: true, source: "manual",
      price_override_cents: price_override_cents
    )
    builder.run!
    builder.stay
  end

  subject(:draft) { described_class.call(stay: source) }

  describe ".call — reconstruction de la composition" do
    let(:source) { build_source_stay }

    it "renvoie un Reservations::Draft" do
      expect(draft).to be_a(Reservations::Draft)
    end

    it "conserve le client (prénom, nom, email)" do
      expect(draft.first_name).to eq("Alice")
      expect(draft.last_name).to eq("Martin")
      expect(draft.email).to eq("alice@example.com")
    end

    it "conserve l'hébergement et son mode d'occupation" do
      expect(draft.lodging_id).to eq(lodging.id)
      expect(draft.booking_type).to eq("lodging")
    end

    it "conserve la composition espace + sa facturation" do
      hall = draft.halls.first
      expect(hall[:kind]).to eq("grande_salle")
      expect(hall[:period]).to eq("journee")
      # Facturation espace reconstruite depuis le SpaceBooking (acompte/caution/mode).
      expect(draft.space_billing[:advance_amount]).to eq("50")
      expect(draft.space_billing[:deposit_amount]).to eq("200")
      expect(draft.space_billing[:payment_method]).to eq("bank_transfer")
    end

    it "conserve les repas (type + convives)" do
      meal = draft.meals.first
      expect(meal[:kind]).to eq("buffet")
      expect(meal[:people]).to eq(3)
    end
  end

  describe ".call — dates vidées (re-planification forcée, anti-surbooking)" do
    let(:source) { build_source_stay }

    it "n'emporte aucune date de séjour" do
      expect(draft.arrival_date).to be_nil
      expect(draft.departure_date).to be_nil
    end

    it "n'emporte aucune date d'élément (espace, repas)" do
      expect(draft.halls.first[:date]).to be_blank
      expect(draft.meals.first[:date]).to be_blank
    end
  end

  describe ".call — paiements et prix imposé jamais copiés" do
    # Source avec un prix imposé ET un paiement encaissé : la duplication ne doit
    # ni figer le prix, ni reprendre le paiement.
    let(:source) do
      stay = build_source_stay(price_override_cents: 99_900)
      Payment.create!(stay: stay, amount_cents: 10_000, status: "paid", payment_method: "card")
      stay
    end

    it "reconstruite puis rebâtie avec de nouvelles dates → aucun paiement, pas d'override" do
      # Le draft dupliqué ne porte pas de prix imposé (attribut absent du Draft) ;
      # l'admin lui redonne de nouvelles dates — au niveau séjour ET des éléments
      # datés (l'espace exige sa date) — et on le rebâtit comme une création normale.
      new_day = Date.today + 60
      draft.arrival_date   = new_day
      draft.departure_date = new_day + 2
      draft.halls = draft.halls.map { |h| h.merge(date: new_day.iso8601) }
      draft.meals = draft.meals.map { |m| m.merge(date: new_day.iso8601) }

      rebuilt = Reservations::Builder.new(draft: draft, admin: true, source: "manual")
      rebuilt.run!
      new_stay = rebuilt.stay

      expect(new_stay.id).not_to eq(source.id)
      expect(new_stay.payments).to be_empty
      expect(new_stay.price_override_cents).to be_nil
      # La composition, elle, est bien répliquée.
      expect(new_stay.stay_items.where(bookable_type: "Booking")).to be_present
      expect(new_stay.stay_items.where(bookable_type: "SpaceBooking")).to be_present
      expect(new_stay.meal_orders).to be_present
    end
  end
end
