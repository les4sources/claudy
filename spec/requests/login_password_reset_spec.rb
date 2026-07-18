require "rails_helper"

# Le flux Devise `recoverable` existait (module actif, colonnes, vues, mailer)
# mais était INACCESSIBLE : le lien « Mot de passe oublié ? » de la page de
# login était commenté et pointait vers `#`. Il sert à la fois à la perte de
# mot de passe ET à la définition initiale du mot de passe d'un compte porteur
# (l'email d'invitation `send_reset_password_instructions`).
RSpec.describe "Connexion — accès au flux mot de passe oublié", type: :request do
  it "la page de login expose un lien vers la réinitialisation du mot de passe" do
    get new_user_session_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include(new_user_password_path)
    expect(response.body).to include("Mot de passe oublié")
  end

  it "la page de réinitialisation est accessible" do
    get new_user_password_path
    expect(response).to have_http_status(:ok)
  end

  it "demander une réinitialisation envoie l'email d'instructions" do
    user = User.create!(email: "porteur@example.com", password: "password123")
    expect {
      post user_password_path, params: { user: { email: user.email } }
    }.to change { ActionMailer::Base.deliveries.size }.by(1)
    expect(ActionMailer::Base.deliveries.last.to).to include("porteur@example.com")
  end
end
