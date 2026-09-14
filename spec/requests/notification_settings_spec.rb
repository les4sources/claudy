require "rails_helper"

# Epic #242, phase 2, décision 3 — Paramètres > Notifications : qui est « la
# comptabilité ».
RSpec.describe "Paramètres > Notifications", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user) { User.create!(email: "admin-notif@les4sources.be", password: "password123") }
  before { sign_in user }

  it "affiche les destinataires enregistrés" do
    Setting.set(NotificationSettingsController::ACCOUNTING_EMAILS_KEY, "compta@les4sources.be")

    get notification_settings_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("compta@les4sources.be")
  end

  it "accepte plusieurs adresses, quel que soit le séparateur" do
    patch notification_settings_path, params: {
      notification_settings: { accounting_notification_emails: "compta@les4sources.be; tresorerie@les4sources.be\nautre@les4sources.be" }
    }

    expect(response).to redirect_to(notification_settings_path)
    expect(NotificationSettingsController.accounting_emails)
      .to eq(%w[compta@les4sources.be tresorerie@les4sources.be autre@les4sources.be])
  end

  it "refuse une adresse invalide et ne touche à rien" do
    Setting.set(NotificationSettingsController::ACCOUNTING_EMAILS_KEY, "compta@les4sources.be")

    patch notification_settings_path, params: {
      notification_settings: { accounting_notification_emails: "compta@les4sources.be, pas-une-adresse" }
    }

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.body).to include("Adresse invalide")
    expect(NotificationSettingsController.accounting_emails).to eq(["compta@les4sources.be"])
  end

  it "retrouve les comptes derrière les adresses" do
    compta = User.create!(email: "Compta@les4sources.be", password: "password123")
    Setting.set(NotificationSettingsController::ACCOUNTING_EMAILS_KEY, "compta@les4sources.be, inconnu@ailleurs.be")

    expect(NotificationSettingsController.accounting_users.to_a).to eq([compta])
  end
end
