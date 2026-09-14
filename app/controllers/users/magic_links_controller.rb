module Users
  # Connexion par lien e-mail pour les comptes Devise (issue #306).
  #
  # UN SEUL CLIC. Le lien reçu ouvre la session directement : le `GET` vérifie
  # le jeton, le consomme, et connecte. Pas de page de confirmation, pas de
  # bouton à cliquer — décision de cadrage de Michael.
  #
  # Contrepartie assumée : un antivirus ou un proxy de tracking qui suivrait les
  # liens d'un e-mail consommerait le jeton avant l'utilisateur. Deux garde-fous
  # rendent ce cas marginal — le tracking de liens Postmark est désactivé sur ce
  # mail (`UserMailer#magic_link`), et un lien mort renvoie sur une page qui
  # permet d'en redemander un immédiatement.
  #
  # ANTI-ÉNUMÉRATION. Le `POST` répond RIGOUREUSEMENT la même chose que
  # l'adresse existe ou non : même redirection, même message, même statut. C'est
  # la seule façon de ne pas transformer ce formulaire en annuaire des comptes.
  # Toute la logique tient donc dans un `if` sans `else`.
  class MagicLinksController < ApplicationController
    # Le gabarit des écrans Devise : pas de barre de navigation, pas de pied de
    # page « Me déconnecter ». Sans lui, Rails retomberait sur `application` et
    # cette porte ressemblerait à une page de l'app, connectée, alors qu'on ne
    # l'est pas encore.
    layout "devise"

    before_action :redirect_if_signed_in, only: %i[new create sent]

    def new; end

    def create
      email = params[:email].to_s.strip.downcase
      user = User.find_by(email: email)

      if eligible?(user) && !UserLoginLink.throttled?(user)
        link, token = UserLoginLink.issue!(user)
        UserMailer.magic_link(user: user, token: token, expires_at: link.expires_at).deliver_later
      end

      # PRG : l'adresse saisie ne transite pas dans l'URL, et un rafraîchissement
      # de la page de confirmation ne renvoie pas un second mail.
      redirect_to sent_user_magic_link_path, notice: t("users.magic_link.sent")
    end

    # GET /users/magic_link/:token — le clic depuis l'e-mail.
    def show
      link = UserLoginLink.find_usable(params[:token])
      user = link&.user

      return refuse unless link && eligible?(user)

      # La consommation et l'ouverture de session tiennent dans une seule
      # transaction : si `sign_in` échoue, le lien n'est pas brûlé et
      # l'utilisateur peut recliquer au lieu de redemander un mail.
      ActiveRecord::Base.transaction do
        link.consume!
        sign_in(:user, user)
      end

      redirect_to after_sign_in_path_for(user)
    end

    def sent; end

    private

    # Un compte dont le membre d'équipe a été désactivé n'entre pas par le mot
    # de passe (`User#active_for_authentication?`) : il n'entrera pas non plus
    # par ici. `sign_in` ne consulte pas cette méthode — c'est à nous de le
    # faire, sinon le lien e-mail serait une porte plus permissive que l'autre.
    def eligible?(user)
      user.present? && user.active_for_authentication?
    end

    # Jeton inconnu, expiré, consommé, ou compte désactivé : un seul et même
    # message. Dire laquelle des causes s'applique renseignerait un attaquant
    # sur ce qu'il a trouvé.
    def refuse
      redirect_to new_user_magic_link_path, alert: t("users.magic_link.invalid")
    end

    def redirect_if_signed_in
      redirect_to root_path if user_signed_in?
    end
  end
end
