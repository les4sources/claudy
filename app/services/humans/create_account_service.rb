module Humans
  # Crée un compte d'accès (User Devise) lié à un Human, pour qu'un porteur
  # d'activité puisse se connecter à Claudy et gérer ses disponibilités.
  # Epic #25 — Phase 2 (comptes porteurs).
  #
  # Le mot de passe est aléatoire ; par défaut un email d'invitation
  # (« définir votre mot de passe ») est envoyé via le flux Devise de
  # réinitialisation. Passer `send_invitation: false` pour un backfill silencieux.
  class CreateAccountService < ServiceBase
    attr_reader :human, :user

    def initialize(human:, send_invitation: true)
      @human = human
      @send_invitation = send_invitation
      @report_errors = true
    end

    def run
      catch_error(context: { human_id: human&.id }) do
        run!
      end
    end

    def run!
      if human.email.blank?
        set_error_message("#{human.name} n'a pas d'adresse email — ajoutez-en une avant de créer un compte.")
        return false
      end

      if human.user.present?
        set_error_message("#{human.name} a déjà un compte d'accès.")
        return false
      end

      if User.exists?(email: human.email)
        set_error_message("Un compte existe déjà avec l'adresse #{human.email}.")
        return false
      end

      @user = User.new(
        email: human.email,
        password: SecureRandom.hex(24),
        human: human
      )
      @user.save!
      @user.send_reset_password_instructions if @send_invitation
      true
    end
  end
end
