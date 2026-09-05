require "rails_helper"

# Cuisine (epic #219, phase 1) — la réconciliation par IDENTIFIANT.
#
# Avant : chaque édition de séjour soft-deletait toutes les lignes de repas et
# les recréait. Tout ce que la ligne porte désormais — la validation de la
# cuisine, le responsable, un prix corrigé à la main, les coûts — n'aurait pas
# survécu à une correction d'heure d'arrivée. Ces exemples verrouillent l'inverse.
RSpec.describe "Cuisine — réconciliation des lignes à l'édition du séjour" do
  let(:day)  { Date.today + 30 }
  let(:day2) { Date.today + 31 }

  def base_draft(meals:)
    Reservations::Draft.new(
      arrival_date: day.iso8601, departure_date: (day + 1).iso8601,
      dogs_count: 0, first_name: "Camille", last_name: "Martin",
      email: "camille@example.com", phone: "+32470112233",
      meals: meals
    )
  end

  def build_stay!(meals:)
    b = Reservations::Builder.new(draft: base_draft(meals: meals), admin: true, source: "manual")
    raise "build failed: #{b.error_message}" unless b.run
    b.stay
  end

  def update!(stay, meals:)
    updater = Stays::AdminUpdater.new(stay: stay, draft: base_draft(meals: meals))
    raise "update failed: #{updater.error_message}" unless updater.run

    stay.reload
  end

  # Le draft tel que le formulaire du séjour le renvoie : les lignes existantes
  # portent leur id, les nouvelles n'en ont pas.
  def draft_rows(stay, extra = [])
    Stays::DraftReconstructor.call(stay).meals.map(&:symbolize_keys) + extra
  end

  it "reconstruit les lignes actives avec leur id, leur moment et leurs notes" do
    stay = build_stay!(meals: [{ kind: "repas", date: day.iso8601, moment: "soir",
                                 people: 12, notes: "deux véganes" }])
    line = stay.meal_orders.sole

    expect(draft_rows(stay)).to eq([{ id: line.id, kind: "repas", date: day.iso8601,
                                      moment: "soir", people: 12, notes: "deux véganes" }])
  end

  it "met la ligne à jour EN PLACE : l'identifiant survit à l'édition" do
    stay = build_stay!(meals: [{ kind: "repas", date: day.iso8601, people: 12 }])
    line = stay.meal_orders.sole

    rows = draft_rows(stay)
    rows[0] = rows[0].merge(people: 15, moment: "midi")
    update!(stay, meals: rows)

    expect(stay.meal_orders.pluck(:id)).to eq([line.id])
    expect(line.reload.people).to eq(15)
    expect(line.moment).to eq("midi")
    expect(line.price_cents).to eq(22_500) # 15 €/pers × 15
    expect(stay.total_amount_cents).to eq(22_500)
  end

  it "conserve le prix corrigé, le responsable et les coûts, que le form ignore" do
    stay = build_stay!(meals: [{ kind: "repas", date: day.iso8601, people: 12 }])
    steph = Human.create!(name: "Stéphanie", email: "steph@les4sources.be")
    line  = stay.meal_orders.sole
    line.update!(unit_price_cents: 2_200, responsible_human: steph,
                 status: "confirmed", cost_cents: 9_000, cost_notes: "courses")

    rows = draft_rows(stay).map { |r| r.merge(notes: "sans lactose") }
    update!(stay, meals: rows)

    line.reload
    expect(line.unit_price_cents).to eq(2_200)
    expect(line.responsible_human).to eq(steph)
    expect(line.status).to eq("confirmed")
    expect(line.cost_cents).to eq(9_000)
    expect(line.notes).to eq("sans lactose")
    expect(line.price_cents).to eq(26_400) # 22 € × 12, l'override tient
  end

  it "remet la validation en attente quand le nombre de convives change" do
    stay = build_stay!(meals: [{ kind: "repas", date: day.iso8601, people: 12 }])
    line = stay.meal_orders.sole
    line.update!(validation: "accepted", validated_at: Time.current)

    rows = draft_rows(stay)
    update!(stay, meals: [rows[0].merge(people: 20)])

    expect(line.reload.validation).to eq("pending")
    expect(line.validated_at).to be_nil
  end

  it "ne touche pas à la validation quand rien de sensible ne change" do
    stay = build_stay!(meals: [{ kind: "repas", date: day.iso8601, people: 12 }])
    line = stay.meal_orders.sole
    line.update!(validation: "accepted", validated_at: Time.current)

    update!(stay, meals: draft_rows(stay))

    expect(line.reload.validation).to eq("accepted")
  end

  it "annule la ligne retirée du séjour au lieu de la supprimer" do
    stay = build_stay!(meals: [{ kind: "repas", date: day.iso8601, people: 12 }])
    line = stay.meal_orders.sole

    update!(stay, meals: [{ kind: "buffet_vege", date: day2.iso8601, people: 8 }])

    expect(line.reload.status).to eq("cancelled")
    expect(line.cancellation_reason).to eq("Retirée du séjour")
    expect(line.deleted_at).to be_nil
    expect(stay.meal_orders.active.map(&:kind)).to eq(["buffet_vege"])
    expect(stay.total_amount_cents).to eq(9_600) # seul le buffet compte
  end

  it "crée les lignes sans id et ignore un id étranger au séjour" do
    stay  = build_stay!(meals: [{ kind: "repas", date: day.iso8601, people: 12 }])
    other = build_stay!(meals: [{ kind: "apero", date: day.iso8601, people: 4 }])
    intruder = other.meal_orders.sole

    rows = draft_rows(stay, [{ kind: "buffet_viande", date: day2.iso8601, people: 8 },
                             { id: intruder.id, kind: "trio", date: day2.iso8601, people: 99 }])
    update!(stay, meals: rows)

    expect(stay.meal_orders.active.pluck(:kind)).to match_array(%w[repas buffet_viande])
    expect(intruder.reload.stay_id).to eq(other.id)
    expect(intruder.people).to eq(4)
  end

  it "exclut une demande d'info du total du séjour" do
    stay = build_stay!(meals: [{ kind: "repas", date: day.iso8601, people: 12 }])
    expect(stay.total_amount_cents).to eq(18_000)

    stay.meal_orders.sole.update!(status: "inquiry")
    stay.recompute_aggregates!

    expect(stay.reload.total_amount_cents).to eq(0)
  end
end
