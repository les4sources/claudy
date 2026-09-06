require "rails_helper"

# Une demande de modification client approuvée ne doit PAS effacer ce que
# l'équipe a ajouté entre la soumission et l'approbation (revue de l'epic #219).
RSpec.describe "Demande de modification — composition ajoutée entre-temps" do
  let(:day) { Date.today + 30 }

  def base_draft(meals: [])
    Reservations::Draft.new(
      arrival_date: day.iso8601, departure_date: (day + 1).iso8601,
      dogs_count: 0, first_name: "Camille", last_name: "Martin",
      email: "camille-cr@example.com", phone: "+32470112233",
      meals: meals
    )
  end

  it "conserve un buffet posé après la soumission de la demande" do
    builder = Reservations::Builder.new(draft: base_draft(meals: [{ kind: "repas", date: day.iso8601, people: 10 }]),
                                        admin: true, source: "manual")
    raise "build failed" unless builder.run

    stay = builder.stay
    # Le client soumet sa demande : le snapshot fige la composition d'AUJOURD'HUI.
    request = StayChangeRequest.create!(
      stay: stay, status: "pending",
      draft_snapshot: Stays::DraftReconstructor.call(stay).to_h,
      new_total_cents: stay.total_amount_cents
    )

    # L'accueil ajoute un buffet, et corrige les convives du repas.
    buffet = stay.meal_orders.create!(kind: "buffet_vege", date: day.iso8601, people: 30)
    repas  = stay.meal_orders.find_by(kind: "repas")
    repas.update!(people: 14, validation: "accepted", validated_at: Time.current)

    expect(Stays::ApplyChangeRequest.new(change_request: request.reload).run).to be(true)

    expect(buffet.reload.status).to eq("requested")
    expect(repas.reload.people).to eq(14)
    expect(repas.validation).to eq("accepted")
  end
end
