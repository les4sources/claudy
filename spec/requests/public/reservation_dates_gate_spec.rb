require "rails_helper"

# Étape 1 du funnel public (Michael 2026-07-23) : les dates sont OBLIGATOIRES
# pour passer à la composition, et l'info « chambres en semaine » est affichée
# dès cette étape.
RSpec.describe "Funnel public — étape dates", type: :request do
  it "affiche l'information chambres en semaine dès l'étape 1" do
    get public_reservation_dates_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("chambres et lits")
    expect(response.body).to include("35")
  end

  it "refuse d'avancer sans dates (POST direct, contournement du required HTML)" do
    post public_reservation_advance_dates_path, params: { reservation: { arrival_date: "", departure_date: "" } }

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.body).to include("Choisissez vos dates")
  end

  it "refuse d'avancer avec seulement une arrivée" do
    post public_reservation_advance_dates_path,
         params: { reservation: { arrival_date: (Date.current + 10).iso8601, departure_date: "" } }

    expect(response).to have_http_status(:unprocessable_entity)
  end

  it "avance vers la composition avec deux dates valides" do
    post public_reservation_advance_dates_path,
         params: { reservation: { arrival_date: (Date.current + 10).iso8601,
                                  departure_date: (Date.current + 12).iso8601 } }

    expect(response).to redirect_to(public_reservation_compose_path)
  end

  it "rend les deux champs dates required côté HTML" do
    get public_reservation_dates_path

    expect(response.body.scan(/name="reservation\[(?:arrival|departure)_date\]"[^>]*required/).size)
      .to eq(2).or satisfy { response.body.scan(/required[^>]*name="reservation\[(?:arrival|departure)_date\]"/).size == 2 }
  end
end
