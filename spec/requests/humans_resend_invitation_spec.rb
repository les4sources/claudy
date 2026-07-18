require "rails_helper"

# Bouton « Renvoyer l'invitation » sur la fiche porteur : re-déclenche l'email de
# définition / réinitialisation du mot de passe pour un compte existant (utile si
# l'invitation initiale a échoué, ex. bug Postmark).
RSpec.describe "Humans — renvoyer l'invitation d'accès", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:admin) { User.create!(email: "staff@les4sources.be", password: "password123") }
  before { sign_in admin }

  it "renvoie l'email d'invitation à un porteur qui a déjà un compte" do
    porteur = Human.create!(name: "Porteur", email: "porteur@example.com")
    Humans::CreateAccountService.new(human: porteur, send_invitation: false).run
    expect(porteur.reload.user).to be_present

    expect {
      post resend_invitation_human_path(porteur)
    }.to change { ActionMailer::Base.deliveries.size }.by(1)

    expect(response).to redirect_to(human_path(porteur))
    expect(ActionMailer::Base.deliveries.last.to).to include("porteur@example.com")
  end

  it "refuse (sans email) si le porteur n'a pas encore de compte" do
    porteur = Human.create!(name: "Sans compte", email: "sanscompte@example.com")

    expect {
      post resend_invitation_human_path(porteur)
    }.not_to change { ActionMailer::Base.deliveries.size }

    expect(response).to redirect_to(human_path(porteur))
    expect(flash[:alert]).to be_present
  end
end
