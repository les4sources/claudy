require "rails_helper"

# L'adresse de connexion suit l'email de la fiche membre (Émilie, 2026-10-15 :
# fiche en gmail, compte resté sur communication@, liens partis au mauvais
# endroit).
RSpec.describe "Humans — l'adresse de connexion suit la fiche", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:admin) { User.create!(email: "staff@les4sources.be", password: "password123") }
  let!(:emilie) { Human.create!(name: "Émilie", email: "communication@les4sources.be") }
  let!(:compte) { User.create!(email: "communication@les4sources.be", password: "password123", human: emilie) }

  before { sign_in admin }

  def changer_email(email)
    patch human_path(emilie), params: { human: { email: email } }
  end

  it "change l'adresse de connexion quand l'email de la fiche change" do
    changer_email("Snoapsavons@gmail.com ")

    expect(response).to redirect_to(human_path(emilie))
    expect(compte.reload.email).to eq("snoapsavons@gmail.com")
  end

  it "ne touche pas le compte si l'email de la fiche ne change pas" do
    emilie.update_column(:email, "snoapsavons@gmail.com")

    patch human_path(emilie), params: { human: { name: "Émilie T." } }

    expect(compte.reload.email).to eq("communication@les4sources.be")
  end

  it "refuse tout si l'adresse sert déjà à un autre compte" do
    User.create!(email: "pris@example.com", password: "password123")

    changer_email("pris@example.com")

    expect(response).to have_http_status(:unprocessable_entity)
    expect(emilie.reload.email).to eq("communication@les4sources.be")
    expect(compte.reload.email).to eq("communication@les4sources.be")
  end

  it "laisse le compte en place quand on vide l'email de la fiche" do
    changer_email("")

    expect(compte.reload.email).to eq("communication@les4sources.be")
  end

  describe "un compte déjà désaccordé" do
    before { emilie.update_column(:email, "snoapsavons@gmail.com") }

    it "montre l'écart sur la fiche et propose de l'aligner" do
      get human_path(emilie)

      expect(response.body).to include("Se connecter avec snoapsavons@gmail.com")
      expect(response.body).to include(sync_account_email_human_path(emilie))
    end

    it "aligne l'adresse de connexion d'un clic" do
      post sync_account_email_human_path(emilie)

      expect(response).to redirect_to(human_path(emilie))
      expect(compte.reload.email).to eq("snoapsavons@gmail.com")
    end

    it "ne montre rien quand les deux adresses concordent" do
      compte.update!(email: "snoapsavons@gmail.com")

      get human_path(emilie)

      expect(response.body).not_to include("Se connecter avec")
    end
  end

  it "annonce l'invitation renvoyée à l'adresse de connexion, pas à celle de la fiche" do
    emilie.update_column(:email, "snoapsavons@gmail.com")

    post resend_invitation_human_path(emilie)

    expect(flash[:notice]).to include("communication@les4sources.be")
    expect(ActionMailer::Base.deliveries.last.to).to eq(["communication@les4sources.be"])
  end
end
