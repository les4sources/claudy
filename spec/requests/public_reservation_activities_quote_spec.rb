require "rails_helper"

# Epic #55, Phase 4 — l'étape « Activités » du funnel recalcule le devis en
# direct (demande Michael 2026-08-21). Jusqu'ici le panneau latéral restait figé
# sur son état d'entrée d'étape : on saisissait deux participants et le total ne
# bougeait qu'à l'étape suivante.
RSpec.describe "Funnel /reservation — devis de l'étape activités", type: :request do
  let(:porteur)      { Human.create!(name: "Porteuse", email: "porteuse@example.com") }
  let(:experience)   { Experience.create!(name: "Vannerie", human: porteur, fixed_price_cents: 5_000, price_cents: 1_500) }
  let(:availability) { ExperienceAvailability.create!(experience: experience, available_on: Date.today + 21, starts_at: "10:00") }

  # Un séjour en cours de composition : dates posées, hébergement choisi.
  def start_draft
    post public_reservation_advance_dates_path,
         params: { reservation: { arrival_date: (Date.today + 20).to_s,
                                  departure_date: (Date.today + 23).to_s,
                                  adults: 2 } }
  end

  def post_quote(experiences)
    post public_reservation_quote_path,
         params: { reservation: { experiences: experiences } },
         headers: { "Accept" => "text/vnd.turbo-stream.html" }
  end

  before { start_draft }

  it "renvoie un devis incluant l'activité choisie" do
    post_quote([{ id: experience.id, availability_id: availability.id, participants: 2 }])

    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq("text/vnd.turbo-stream.html")
    expect(response.body).to include("reservation_quote")
    expect(response.body).to include("Vannerie")
    # 5 000 + 1 500 × 2 = 8 000.
    expect(response.body).to include("80,00")
  end

  # Le piège du recalcul live : `merge_draft` refuse par principe qu'une valeur
  # vide écrase une ancienne valeur — c'est ce qui permet à chaque étape de ne
  # soumettre que SES champs sans effacer les autres. Sans exception explicite,
  # remettre les participants à zéro laissait l'activité dans le devis, et elle
  # serait partie en réservation malgré le retrait.
  it "retire l'activité du devis quand on efface les participants" do
    post_quote([{ id: experience.id, availability_id: availability.id, participants: 2 }])
    expect(response.body).to include("Vannerie")

    post_quote([{ id: experience.id, availability_id: availability.id, participants: "" }])

    expect(response.body).not_to include("Vannerie")
  end

  it "ne touche pas aux activités quand l'étape suivante ne les resoumet pas" do
    post_quote([{ id: experience.id, availability_id: availability.id, participants: 2 }])

    # L'étape coordonnées ne porte aucun champ `experiences`.
    post public_reservation_quote_path,
         params: { reservation: { first_name: "Vera" } },
         headers: { "Accept" => "text/vnd.turbo-stream.html" }

    expect(response.body).to include("Vannerie")
  end
end
