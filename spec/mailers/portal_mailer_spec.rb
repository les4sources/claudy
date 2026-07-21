require "rails_helper"

# Epic #126, Phase 2 — email du code de connexion au portail.
RSpec.describe PortalMailer, type: :mailer do
  let(:mail) do
    described_class.login_code(email: "ana@example.com",
                               code: "123456",
                               expires_at: 15.minutes.from_now)
  end

  it "porte un sujet clair et part à la bonne adresse" do
    expect(mail.subject).to eq("Votre code de connexion — Les 4 Sources")
    expect(mail.to).to eq(["ana@example.com"])
  end

  it "contient le code et sa durée de validité, en HTML comme en texte" do
    [mail.html_part, mail.text_part].each do |part|
      body = part.body.encoded
      expect(body).to include("123456")
      expect(body).to include("15 minutes")
    end
  end

  it "ne contient aucune donnée de séjour ni de client" do
    body = mail.body.encoded
    expect(body).not_to match(/séjour/i)
    expect(body).not_to include("Ana")
  end
end
