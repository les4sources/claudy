# Emails du portail client (epic #126, Phase 2).
class PortalMailer < ApplicationMailer
  # Code de connexion à usage unique. Texte sobre : le code, sa durée de vie,
  # et rien d'autre — surtout aucune donnée du séjour ni du client.
  def login_code(email:, code:, expires_at:)
    @code = code
    @expires_at = expires_at
    @minutes = PortalOtp::VALIDITY.inspect

    mail(to: email, subject: "Votre code de connexion — Les 4 Sources")
  end

  # L'artisan qui a demandé un lien de connexion à Claudy (la porte de
  # l'équipe) au lieu de passer par son espace : on lui montre sa porte. Pas de
  # code ici — il le demande depuis son espace, adresse déjà remplie.
  def consignor_door(email:)
    @url = portal_url(context: "consignor", email: email)

    mail(to: email, subject: "Votre espace artisan — Les 4 Sources")
  end
end
