module Humans
  # L'adresse de connexion (User#email) suit l'email de la fiche membre.
  #
  # Avant, les deux vivaient chacun de leur côté : on corrigeait l'email de la
  # fiche, et le lien de connexion partait toujours vers l'ancienne adresse
  # (Émilie, 2026-10-15 : sa fiche disait gmail, son compte communication@).
  # Aucun écran ne permettait de corriger le compte.
  #
  # Appelé à la mise à jour de la fiche (quand l'email change) et par le bouton
  # « Se connecter avec l'email de la fiche » (comptes déjà désaccordés).
  class SyncAccountEmailService < ServiceBase
    attr_reader :human

    def initialize(human:)
      @human = human
      @report_errors = true
    end

    def run
      catch_error(context: { human_id: human&.id }) { run! }
    end

    # Lève ServiceError (message pour l'utilisateur) si l'adresse sert déjà à
    # un autre compte : deux comptes ne peuvent pas partager une adresse.
    def run!
      user = human.user
      email = human.email.to_s.strip.downcase
      return true if user.nil? || email.blank? || user.email == email

      if User.where.not(id: user.id).exists?(email: email)
        raise ServiceError, "L'adresse #{email} sert déjà à un autre compte d'accès : " \
                            "celui de #{human.name} n'a pas été modifié."
      end

      user.update!(email: email)
      true
    end
  end
end
