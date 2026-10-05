require "rails_helper"
require Rails.root.join("spec/support/env_helpers")

# Le parcours qu'emprunte claude.ai pour se brancher sur Claudy : découverte,
# enregistrement, consentement d'un humain autorisé, jetons, puis /mcp.
RSpec.describe "Serveur MCP et OAuth", type: :request do
  let(:user) { User.create!(email: "michael@example.com", password: "secret123456") }
  let(:redirect_uri) { "https://claude.ai/api/mcp/auth_callback" }
  let(:verifier) { SecureRandom.urlsafe_base64(48) }
  let(:challenge) { Base64.urlsafe_encode64(Digest::SHA256.digest(verifier), padding: false) }

  around { |example| with_env("MCP_ALLOWED_EMAILS" => "Michael@example.com") { example.run } }

  def json = JSON.parse(response.body)

  def register(uris = [redirect_uri])
    post "/oauth/register", params: { client_name: "Claude", redirect_uris: uris }.to_json,
                            headers: { "CONTENT_TYPE" => "application/json" }
    json
  end

  def authorize_params(client_id)
    { response_type: "code", client_id: client_id, redirect_uri: redirect_uri, code_challenge: challenge,
      code_challenge_method: "S256", state: "xyz" }
  end

  def obtenir_jetons
    client_id = register["client_id"]
    sign_in user
    get "/oauth/authorize", params: authorize_params(client_id)
    expect(response.body).to include("Brancher Claude sur Claudy", "Autoriser")
    post "/oauth/authorize", params: authorize_params(client_id).merge(decision: "allow")
    expect(response.location).to start_with("#{redirect_uri}?")
    query = Rack::Utils.parse_query(URI.parse(response.location).query)
    expect(query["state"]).to eq("xyz")
    post "/oauth/token", params: { grant_type: "authorization_code", code: query["code"], client_id: client_id,
                                   redirect_uri: redirect_uri, code_verifier: verifier }
    [client_id, json]
  end

  def mcp(body, token)
    post "/mcp", params: body.to_json,
                 headers: { "CONTENT_TYPE" => "application/json", "Authorization" => "Bearer #{token}" }
  end

  it "annonce le serveur d'autorisation et refuse /mcp sans jeton" do
    get "/.well-known/oauth-protected-resource"
    expect(json).to include("resource" => "http://www.example.com/mcp", "authorization_servers" => ["http://www.example.com"])

    get "/.well-known/oauth-authorization-server"
    expect(json["code_challenge_methods_supported"]).to eq(["S256"])

    mcp({ jsonrpc: "2.0", id: 1, method: "tools/list" }, "nope")
    expect(response).to have_http_status(:unauthorized)
    expect(response.headers["WWW-Authenticate"]).to include("resource_metadata=")
  end

  it "refuse d'enregistrer une adresse de retour étrangère à Claude" do
    register(["https://evil.example/callback"])
    expect(response).to have_http_status(:bad_request)
  end

  it "mène du consentement aux outils, et le jeton de rafraîchissement tourne" do
    client_id, jetons = obtenir_jetons
    expect(jetons).to include("token_type" => "Bearer", "access_token" => be_present)

    mcp({ jsonrpc: "2.0", id: 1, method: "tools/list" }, jetons["access_token"])
    expect(json.dig("result", "tools").pluck("name")).to include("diagnostic_compte")

    post "/oauth/token", params: { grant_type: "refresh_token", refresh_token: jetons["refresh_token"], client_id: client_id }
    expect(response).to have_http_status(:ok)
    post "/oauth/token", params: { grant_type: "refresh_token", refresh_token: jetons["refresh_token"], client_id: client_id }
    expect(response).to have_http_status(:bad_request)

    mcp({ jsonrpc: "2.0", id: 2, method: "ping" }, jetons["access_token"])
    expect(response).to have_http_status(:unauthorized)
  end

  it "refuse un code présenté sans le bon vérificateur PKCE" do
    client_id = register["client_id"]
    sign_in user
    post "/oauth/authorize", params: authorize_params(client_id).merge(decision: "allow")
    code = Rack::Utils.parse_query(URI.parse(response.location).query)["code"]

    post "/oauth/token", params: { grant_type: "authorization_code", code: code, client_id: client_id,
                                   redirect_uri: redirect_uri, code_verifier: "mauvais" }
    expect(json["error"]).to eq("invalid_grant")
  end

  it "ferme la porte à un compte absent de MCP_ALLOWED_EMAILS" do
    autre = User.create!(email: "autre@example.com", password: "secret123456")
    client_id = register["client_id"]
    sign_in autre
    get "/oauth/authorize", params: authorize_params(client_id)
    expect(response).to have_http_status(:forbidden)
  end
end
