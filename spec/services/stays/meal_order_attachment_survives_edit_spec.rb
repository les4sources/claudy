require "rails_helper"

# Issue #315 — LE piège de la fonctionnalité, prouvé plutôt que supposé.
#
# `MealComposition#reconcile_meals!` termine par : toute ligne active du séjour
# absente du formulaire soumis passe en `cancelled`, motif « Retirée du séjour ».
# Une demande rattachée APRÈS coup n'a jamais été saisie depuis le formulaire du
# séjour — si elle n'en revenait pas, la première édition du séjour l'effacerait
# en silence, et le rattachement se déferait tout seul.
#
# Elle devrait survivre : `Stays::DraftReconstructor#meals_from_stay` reconstruit
# toutes les lignes ACTIVES du séjour avec leur `id`, donc elle revient dans le
# draft et `reconcile_meals!` la met à jour. C'est ce qu'on vérifie ici.
RSpec.describe "Séjour — une demande de cuisine rattachée survit à une édition", type: :model do
  let!(:lodging) { Lodging.create!(name: "La Hulotte", summary: "gîte") }
  let(:arrival)   { Date.today + 30 }
  let(:departure) { Date.today + 32 }

  def build_draft(overrides = {})
    Reservations::Draft.new({
      lodging_id: lodging.id, arrival_date: arrival, departure_date: departure,
      adults: 2, first_name: "Alice", last_name: "Martin",
      email: "attach-meal@example.com", phone: "0470111222"
    }.merge(overrides))
  end

  let(:stay) do
    Reservations::Builder.new(draft: build_draft, admin: true, status: "pending", source: "manual")
                         .tap(&:run!).stay
  end

  # La demande telle que Malau l'a prise au téléphone : sans séjour, avec le nom
  # du groupe en texte libre.
  let(:order) do
    MealOrder.create!(kind: "repas", moment: "midi", people: 12, date: arrival + 1,
                      status: "requested", contact_label: "École de Godinne",
                      skip_notifications: true)
  end

  it "reste active après une édition du séjour via AdminUpdater" do
    order.attach_to_stay!(stay)

    # Le formulaire d'édition repart du draft reconstruit — exactement ce que
    # fait `StaysController#edit` puis `#update`.
    draft = Stays::DraftReconstructor.new(stay.reload).to_draft
    Stays::AdminUpdater.new(stay: stay, draft: draft).run!

    order.reload
    expect(order.status).to eq("requested")
    expect(order.cancellation_reason).to be_blank
    expect(order.stay_id).to eq(stay.id)
    expect(stay.reload.meal_orders.active).to include(order)
  end

  it "le draft reconstruit la reprend avec son id" do
    order.attach_to_stay!(stay)

    draft = Stays::DraftReconstructor.new(stay.reload).to_draft
    ids = Array(draft.meals).map { |meal| meal[:id] || meal["id"] }

    expect(ids).to include(order.id)
  end

  it "entre dans le total du séjour après recalcul" do
    order.update!(unit_price_cents: 2_000)
    order.attach_to_stay!(stay)

    draft = Stays::DraftReconstructor.new(stay.reload).to_draft
    Stays::AdminUpdater.new(stay: stay, draft: draft).run!

    expect(stay.reload.meal_orders.billable.sum(:price_cents)).to eq(24_000)
  end
end
