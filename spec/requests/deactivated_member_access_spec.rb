require "rails_helper"

# Addendum 3/4 — un compte rattaché à un membre d'équipe désactivé
# (`status: "inactive"`) ne peut plus accéder à l'app : même une session déjà
# ouverte est coupée à la requête suivante (BaseController#enforce_active_member).
RSpec.describe "Blocage d'accès des membres désactivés", type: :request do
  include Devise::Test::IntegrationHelpers

  it "coupe la session d'un compte dont le membre a été désactivé" do
    human = Human.create!(name: "Membre Bientot Inactif", status: "active")
    user = User.create!(email: "bientot-inactif@les4sources.be",
                        password: "password123", human: human)
    sign_in user

    # Accès normal tant que le membre est actif.
    get root_path
    expect(response).to have_http_status(:ok)

    # Désactivation du membre → la session est coupée à la requête suivante.
    human.update_column(:status, "inactive")

    get root_path
    expect(response).to redirect_to(new_user_session_path)
  end

  it "laisse passer un compte admin sans membre lié" do
    admin = User.create!(email: "admin-libre@les4sources.be", password: "password123")
    sign_in admin

    get root_path
    expect(response).to have_http_status(:ok)
  end
end
