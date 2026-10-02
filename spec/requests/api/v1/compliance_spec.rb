require "rails_helper"

# L'échéancier comptable par l'API — le chemin de la reprise depuis Notion.
RSpec.describe "API v1 — échéancier comptable", type: :request do
  let(:token) { "jeton-echeancier" }
  let(:headers) { { "Authorization" => "Bearer #{token}", "CONTENT_TYPE" => "application/json" } }

  before { ENV["AGENT_API_TOKEN"] = token }
  after { ENV.delete("AGENT_API_TOKEN") }

  def body = JSON.parse(response.body)

  let!(:srl) { LegalEntity.create!(name: "SRL de test", form: "srl", vat_regime: "subject") }
  let!(:michael) { User.create!(email: "michael-api@les4sources.be", password: "password123") }

  let(:tva) do
    { compliance_obligation: { title: "Déclaration TVA", legal_entity_name: "SRL de test", frequency: "quarterly",
                               first_due_on: "2025-04-20", covers: "previous",
                               responsible_email: "MICHAEL-API@les4sources.be" } }
  end

  it "crée une obligation, génère ses échéances, et ne double rien quand on rejoue" do
    post "/api/v1/compliance_obligations", params: tva.to_json, headers: headers

    expect(response).to have_http_status(:created)
    expect(body.dig("data", "responsible_email")).to eq("michael-api@les4sources.be")
    labels = body.dig("data", "deadlines").map { |deadline| deadline["period_label"] }
    expect(labels.first(4)).to eq(["T1 2025", "T2 2025", "T3 2025", "T4 2025"])

    post "/api/v1/compliance_obligations", params: tva.to_json, headers: headers

    expect(response).to have_http_status(:ok)
    expect(ComplianceObligation.count).to eq(1)
  end

  it "refuse une entité inconnue en le disant" do
    post "/api/v1/compliance_obligations",
         params: { compliance_obligation: tva[:compliance_obligation].merge(legal_entity_name: "SPRL") }.to_json,
         headers: headers

    expect(response).to have_http_status(:unprocessable_entity)
    expect(body["message"]).to eq("Entité inconnue : SPRL.")
  end

  it "reprend l'historique : une échéance passée se clôt à la date réelle du dépôt" do
    post "/api/v1/compliance_obligations", params: tva.to_json, headers: headers
    t1 = ComplianceDeadline.find_by(period_start: Date.new(2025, 1, 1))

    patch "/api/v1/compliance_deadlines/#{t1.id}",
          params: { compliance_deadline: { status: "done", done_on: "2025-04-18" } }.to_json, headers: headers

    expect(response).to have_http_status(:ok)
    expect(body.dig("data", "effective_status")).to eq("done")
    expect(t1.reload.done_on).to eq(Date.new(2025, 4, 18))

    get "/api/v1/compliance_deadlines", params: { outstanding: true }, headers: { "Authorization" => "Bearer #{token}" }
    expect(body["data"].map { |deadline| deadline["id"] }).not_to include(t1.id)
  end
end
