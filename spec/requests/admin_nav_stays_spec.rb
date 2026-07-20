require "rails_helper"

# Menu principal admin (epic #81) — le séjour devient le point d'entrée unique :
# l'entrée « Séjours » remplace « Hébergements » / « Espaces » dans la nav.
RSpec.describe "Nav admin — entrée Séjours", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user) { User.create!(email: "agent-nav@les4sources.be", password: "password123") }
  before { sign_in user }

  # On rend une page admin quelconque servie AVEC le layout (donc la navbar) :
  # /stays/recents. Son propre contenu ne mentionne pas « Hébergements », ce qui
  # isole l'assertion à la navigation.
  it "expose « Séjours » et retire « Hébergements » du menu principal" do
    get recent_stays_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Séjours")
    expect(response.body).to include(%(href="#{stays_path}"))
    expect(response.body).not_to include("Hébergements")
  end
end
