require "rails_helper"

# Issue #306 — connexion par lien e-mail pour les comptes Devise.
#
# Le cœur de ces tests est l'ANTI-ÉNUMÉRATION : la réponse à une adresse
# inconnue doit être rigoureusement indiscernable de la réponse à une adresse
# connue. On ne s'en assure pas en relisant le code — on compare les deux
# réponses, octet pour octet.
RSpec.describe "Connexion par lien e-mail", type: :request, queue_adapter: :test do
  include ActiveSupport::Testing::TimeHelpers
  include ActiveJob::TestHelper

  let!(:user) { User.create!(email: "steph@les4sources.be", password: "password123") }

  def demander(email)
    post user_magic_links_path, params: { email: email }
  end

  describe "GET /users/magic_link/new" do
    it "affiche le formulaire à un seul champ" do
      get new_user_magic_link_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('name="email"')
      expect(response.body).to include("Se connecter par e-mail")
    end

    it "renvoie un utilisateur déjà connecté vers la racine" do
      sign_in user

      get new_user_magic_link_path

      expect(response).to redirect_to(root_path)
    end
  end

  describe "POST /users/magic_link" do
    it "émet un lien et met un mail en file pour une adresse connue" do
      expect { demander("steph@les4sources.be") }
        .to change(UserLoginLink, :count).by(1)
        .and have_enqueued_mail(UserMailer, :magic_link)

      expect(UserLoginLink.last.user).to eq(user)
    end

    it "normalise l'adresse saisie (espaces, majuscules)" do
      expect { demander("  STEPH@LES4SOURCES.BE  ") }
        .to change(UserLoginLink, :count).by(1)
    end

    it "n'émet rien et n'envoie rien pour une adresse inconnue" do
      expect { demander("inconnu@example.com") }.not_to change(UserLoginLink, :count)
      expect(enqueued_jobs).to be_empty
    end

    # LE test d'anti-énumération : on compare les deux réponses.
    it "répond exactement la même chose à une adresse connue et à une inconnue" do
      demander("steph@les4sources.be")
      connue = [ response.status, response.location, flash[:notice], response.body ]

      demander("inconnu@example.com")
      inconnue = [ response.status, response.location, flash[:notice], response.body ]

      expect(inconnue).to eq(connue)
    end

    it "redirige (PRG) sans faire transiter l'adresse dans l'URL" do
      demander("steph@les4sources.be")

      expect(response).to redirect_to(sent_user_magic_link_path)
      expect(response.location).not_to include("steph")
    end

    it "n'envoie plus rien au-delà du rate-limit, sans rien changer à la réponse" do
      5.times { UserLoginLink.issue!(user) }

      demander("steph@les4sources.be")
      bloquee = [ response.status, response.location, flash[:notice] ]

      enqueued_jobs.clear
      demander("steph@les4sources.be")
      expect(enqueued_jobs).to be_empty

      demander("inconnu@example.com")
      expect([ response.status, response.location, flash[:notice] ]).to eq(bloquee)
    end

    # Un compte dont le membre d'équipe est désactivé n'entre pas par le mot de
    # passe : le lien e-mail ne doit pas être une porte plus permissive.
    it "n'émet rien pour un compte dont le membre a été désactivé" do
      human = Human.create!(name: "Partie")
      user.update!(human: human)
      human.update_column(:status, "inactive")

      expect { demander("steph@les4sources.be") }.not_to change(UserLoginLink, :count)
    end
  end

  describe "GET /users/magic_link/:token" do
    it "connecte l'utilisateur et consomme le lien" do
      link, token = UserLoginLink.issue!(user)

      get user_magic_link_path(token: token)

      expect(response).to redirect_to(root_path)
      expect(link.reload.consumed_at).to be_present

      get root_path
      expect(response).to have_http_status(:ok)
    end

    it "refuse un second clic sur le même lien" do
      _, token = UserLoginLink.issue!(user)
      get user_magic_link_path(token: token)

      get user_magic_link_path(token: token)

      expect(response).to redirect_to(new_user_magic_link_path)
      expect(flash[:alert]).to eq(I18n.t("users.magic_link.invalid"))
    end

    it "refuse un lien expiré, avec le même message générique" do
      _, token = UserLoginLink.issue!(user)

      travel 16.minutes do
        get user_magic_link_path(token: token)
      end

      expect(response).to redirect_to(new_user_magic_link_path)
      expect(flash[:alert]).to eq(I18n.t("users.magic_link.invalid"))
    end

    it "refuse un jeton inexistant sans lever d'erreur 500" do
      get user_magic_link_path(token: "ce-jeton-n-a-jamais-existe")

      expect(response).to redirect_to(new_user_magic_link_path)
      expect(flash[:alert]).to eq(I18n.t("users.magic_link.invalid"))
    end

    it "refuse un lien émis avant la désactivation du membre" do
      human = Human.create!(name: "Partie")
      user.update!(human: human)
      _, token = UserLoginLink.issue!(user)
      human.update_column(:status, "inactive")

      get user_magic_link_path(token: token)

      expect(response).to redirect_to(new_user_magic_link_path)
    end

    it "n'ouvre aucune session quand le lien est refusé" do
      get user_magic_link_path(token: "faux")

      get root_path
      expect(response).to redirect_to(new_user_session_path)
    end
  end

  describe "la page de confirmation d'envoi" do
    it "ne dit pas si l'adresse existe" do
      get sent_user_magic_link_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Si un compte existe avec cette adresse")
    end
  end

  describe "la page de connexion par mot de passe" do
    it "propose l'entrée par e-mail à côté du mot de passe oublié" do
      get new_user_session_path

      expect(response.body).to include(new_user_magic_link_path)
      expect(response.body).to include("Se connecter par e-mail")
    end
  end
end
