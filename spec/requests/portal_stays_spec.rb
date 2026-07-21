require "rails_helper"

# Epic #126, Phase 2 — page « Mes séjours » du portail client.
RSpec.describe "Portail client — Mes séjours", type: :request do
  include ActiveJob::TestHelper

  let!(:ana)   { Customer.create!(first_name: "Ana", last_name: "Lopez", email: "ana@example.com") }
  let!(:bruno) { Customer.create!(first_name: "Bruno", last_name: "Roy", email: "bruno@example.com") }

  before { ActionMailer::Base.deliveries.clear }

  def sign_in_portal_as(email)
    perform_enqueued_jobs { post portal_code_path, params: { email: email } }
    code = ActionMailer::Base.deliveries.last.body.encoded[/\b\d{6}\b/]
    post portal_login_path, params: { email: email, code: code }
  end

  def stay_for(customer, arrival:, departure:, notes: nil)
    Stay.create!(customer: customer, source: "manual", status: "confirmed",
                 arrival_date: arrival, departure_date: departure, notes: notes)
  end

  it "exige une session portail" do
    get portal_stays_path
    expect(response).to redirect_to(portal_path)
  end

  it "liste les séjours du client, à venir d'abord, avec badges et lien token" do
    past   = stay_for(ana, arrival: Date.today - 30, departure: Date.today - 28)
    future = stay_for(ana, arrival: Date.today + 10, departure: Date.today + 12)

    sign_in_portal_as("ana@example.com")
    get portal_stays_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Mes séjours")
    expect(response.body).to include(public_stay_path(future.token))
    expect(response.body).to include(public_stay_path(past.token))
    # À venir d'abord.
    expect(response.body.index(future.token)).to be < response.body.index(past.token)
    # Badge de paiement rendu.
    expect(response.body).to include("Voir mon séjour")
  end

  it "ne montre JAMAIS le séjour d'un autre client" do
    mine    = stay_for(ana, arrival: Date.today + 5, departure: Date.today + 7)
    someone = stay_for(bruno, arrival: Date.today + 5, departure: Date.today + 7)

    sign_in_portal_as("ana@example.com")
    get portal_stays_path

    expect(response.body).to include(mine.token)
    expect(response.body).not_to include(someone.token)
    expect(response.body).not_to include("Bruno")
  end

  it "ne fuite aucune note interne" do
    stay_for(ana, arrival: Date.today + 5, departure: Date.today + 7,
                  notes: "NE PAS DIRE AU CLIENT — chien non déclaré")

    sign_in_portal_as("ana@example.com")
    get portal_stays_path

    expect(response.body).not_to include("NE PAS DIRE AU CLIENT")
  end

  it "affiche un état vide propre" do
    sign_in_portal_as("ana@example.com")
    get portal_stays_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Aucun séjour pour l'instant")
  end
end
