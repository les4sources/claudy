# Emails adressés aux comptes Claudy (`User`) — l'équipe et les admins.
class UserMailer < ApplicationMailer
  # Le lien de connexion à usage unique (issue #306). Sobre par construction :
  # le lien, sa durée de vie, et rien d'autre. Aucune donnée métier — ce mail
  # part vers une boîte qu'on n'a pas encore prouvée.
  def magic_link(user:, token:, expires_at:)
    @url = user_magic_link_url(token: token)
    @expires_at = expires_at
    @minutes = (UserLoginLink::VALIDITY / 60).to_i

    # LE TRACKING DE LIENS EST COUPÉ. Postmark réécrit sinon l'URL pour compter
    # les clics, et le premier scanner qui suit le lien réécrit brûlerait le
    # jeton à usage unique avant l'utilisateur. La gem `postmark-rails` lit cet
    # en-tête et le traduit en `TrackLinks` côté API.
    headers["TRACK-LINKS"] = "None"

    mail(to: user.email, subject: "Votre lien de connexion — Claudy")
  end
end
