require "rails_helper"

# Lien d'apporteur (Michael, 2026-10-18) : la page « Les 4 Sources » du site de
# Semisto envoie sur `/reservation?ref=semisto`. Le séjour créé au bout du
# funnel doit porter l'apporteur, pour que l'équipe sache ce qu'elle lui doit.
RSpec.describe "Funnel /reservation — apporteur (?ref=)", type: :request do
  include ActiveJob::TestHelper

  let!(:hulotte) do
    l = Lodging.create!(name: "La Hulotte", price_night_cents: 48_500)
    l.rooms << Room.create!(name: "Chambre 1", level: 1)
    l
  end

  # Un lundi : hors saison, une nuit de week-end isolée est refusée.
  let(:monday) { (Date.today + 60).next_occurring(:monday) }

  def reservation_params(phone: "+32470999888", email: "parrain@example.com")
    { reservation: { lodging_id: hulotte.id, arrival_date: monday.iso8601, departure_date: (monday + 2).iso8601,
                     first_name: "Ada", last_name: "Parrain", email: email, phone: phone } }
  end

  def submit(**opts)
    perform_enqueued_jobs { post "/reservation/coordonnees", params: reservation_params(**opts) }
  end

  it "pose l'apporteur sur le séjour quand on entre par ?ref=semisto" do
    get "/reservation", params: { ref: "semisto" }
    expect(response).to redirect_to("/reservation/sejour")
    get "/reservation/coordonnees"

    expect { submit }.to change(Stay, :count).by(1)
    stay = Stay.last
    expect(stay.referral).to eq("semisto")
    # Le canal ne change pas : c'est le funnel, comme toute demande en ligne.
    expect(stay.source).to eq("reservation")
  end

  it "tolère la casse et les espaces" do
    get "/reservation/sejour", params: { ref: " Semisto " }
    submit
    expect(Stay.last.referral).to eq("semisto")
  end

  it "ignore une clé inconnue" do
    get "/reservation", params: { ref: "nimporte" }
    submit
    expect(Stay.last.referral).to be_nil
  end

  it "ne pose rien sans ?ref=" do
    get "/reservation"
    submit
    expect(Stay.last.referral).to be_nil
  end

  it "garde l'apporteur à travers les étapes et une erreur de validation" do
    get "/reservation", params: { ref: "semisto" }
    # Une clé inconnue plus loin n'efface pas l'apporteur déjà retenu.
    get "/reservation/composer", params: { ref: "inconnu" }

    expect { submit(phone: "abc") }.not_to change(Stay, :count)
    expect(response).to have_http_status(:unprocessable_entity)

    expect { submit }.to change(Stay, :count).by(1)
    expect(Stay.last.referral).to eq("semisto")
  end

  it "repart sans apporteur pour la demande suivante de la même session" do
    get "/reservation", params: { ref: "semisto" }
    submit
    expect(Stay.last.referral).to eq("semisto")

    get "/reservation"
    expect { submit(email: "autre@example.com") }.to change(Stay, :count).by(1)
    expect(Stay.last.referral).to be_nil
  end

  it "signale l'apporteur dans l'email de nouvelle demande à l'équipe" do
    ActionMailer::Base.deliveries.clear
    get "/reservation", params: { ref: "semisto" }
    submit
    textes = ActionMailer::Base.deliveries.map { |m| (m.text_part || m).body.decoded }
    expect(textes.count { |t| t.include?("Apporteur : Semisto") }).to eq(1)
  end
end
