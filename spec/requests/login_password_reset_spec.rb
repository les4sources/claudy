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

# Les écrans Devise avaient gardé les vues générées (anglais, sans style) :
# ils partagent maintenant le gabarit de la page de connexion.
RSpec.describe "Écrans Devise — gabarit et français", type: :request do
  let!(:user) { User.create!(email: "porteur@example.com", password: "password123") }

  it "mot de passe oublié : en français, avec le logo et le retour à la connexion" do
    get new_user_password_path

    expect(response.body).to include("Mot de passe oublié ?")
    expect(response.body).to include("envoyer le lien")
    expect(response.body).to include("les-4-sources-logo-seul")
    expect(response.body).to include(new_user_session_path)
    expect(response.body).not_to include("Forgot your password")
    expect(response.body).not_to include("Sign up")
  end

  it "adresse inconnue : l'erreur s'affiche en français" do
    post user_password_path, params: { user: { email: "personne@example.com" } }

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("n’a pas été trouvé(e)")
  end

  it "après la demande, la page de connexion affiche la confirmation (flash)" do
    post user_password_path, params: { user: { email: user.email } }
    follow_redirect!

    expect(response.body).to include("Vous allez recevoir sous quelques minutes un email")
  end

  it "nouveau mot de passe : la page du lien reçu est en français et l'enregistre" do
    token = user.send_reset_password_instructions

    get edit_user_password_path(reset_password_token: token)
    expect(response.body).to include("Nouveau mot de passe")
    expect(response.body).to include("Enregistrer mon mot de passe")
    expect(response.body).not_to include("Change your password")

    put user_password_path, params: { user: { reset_password_token: token, password: "nouveau-secret", password_confirmation: "nouveau-secret" } }
    expect(user.reload.valid_password?("nouveau-secret")).to be(true)
  end

  it "nouveau mot de passe : un lien périmé le dit en français" do
    put user_password_path, params: { user: { reset_password_token: "faux", password: "nouveau-secret", password_confirmation: "nouveau-secret" } }

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("Clé de réinitialisation du mot de passe")
  end

  it "connexion ratée : le message s'affiche enfin" do
    post user_session_path, params: { user: { email: user.email, password: "mauvais" } }

    expect(response.body).to include("ou mot de passe incorrect")
  end

  it "inscription : en français, sans les liens générés" do
    get new_user_registration_path

    expect(response.body).to include("Créer un compte")
    expect(response.body).not_to include("Sign up")
  end
end

RSpec.describe "Email de mot de passe (aussi l'invitation des porteurs)", type: :request do
  it "est en français et mène à la page du nouveau mot de passe" do
    user = User.create!(email: "porteur@example.com", password: "password123")
    user.send_reset_password_instructions

    mail = ActionMailer::Base.deliveries.last
    expect(mail.body.encoded).to include("Choisir mon mot de passe")
    expect(mail.body.encoded).to include("/users/password/edit?reset_password_token=")
    expect(mail.body.encoded).not_to include("Change my password")
  end
end
