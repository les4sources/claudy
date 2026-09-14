require "rails_helper"

# Issue #306 — l'e-mail qui porte le lien de connexion.
RSpec.describe UserMailer, type: :mailer do
  let(:user) { User.create!(email: "steph@les4sources.be", password: "password123") }
  let(:token) { "un-jeton-en-clair" }
  let(:mail) { described_class.magic_link(user: user, token: token, expires_at: 15.minutes.from_now) }

  it "part à la bonne adresse avec le bon sujet" do
    expect(mail.to).to eq([ "steph@les4sources.be" ])
    expect(mail.subject).to eq("Votre lien de connexion — Claudy")
  end

  it "porte une URL ABSOLUE comportant le jeton" do
    expect(mail.body.encoded).to include("/users/magic_link/#{token}")
    expect(mail.body.encoded).to match(%r{https?://[^/]+/users/magic_link/#{token}})
  end

  it "dit la durée de vie du lien et son usage unique" do
    expect(mail.body.encoded).to include("15 minutes")
    expect(mail.body.encoded).to include("une fois")
  end

  # Un proxy de réécriture d'URL suivrait le lien pour compter le clic, et
  # brûlerait le jeton à usage unique avant l'utilisateur.
  it "coupe le tracking de liens Postmark" do
    expect(mail.track_links).to eq("None")
    expect(mail["TRACK-LINKS"].to_s).to eq("None")
  end

  it "a une version texte et une version HTML" do
    expect(mail.body.parts.map { |part| part.content_type.split(";").first })
      .to include("text/plain", "text/html")
  end

  # Ce mail part vers une boîte dont on n'a pas encore prouvé qu'elle est la
  # bonne : il ne doit rien contenir de métier.
  it "ne porte aucune donnée métier" do
    expect(mail.body.encoded).not_to match(/séjour|client|montant|€/i)
  end
end
