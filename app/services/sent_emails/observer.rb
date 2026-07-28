module SentEmails
  # Observer ActionMailer : notifié APRÈS chaque livraison réelle (cf. Mail
  # `deliver` → `inform_observers`), donc une fois l'en-tête `X-PM-Message-Id`
  # posé par Postmark. Enregistré via `config.action_mailer.observers`.
  #
  # Journaliser ne doit JAMAIS faire échouer un envoi : toute erreur est avalée,
  # tracée dans les logs et remontée à Sentry.
  #
  # La constante est référencée en absolu (`::SentEmails::Recorder`) : Rails
  # garde l'observer enregistré d'un rechargement de code à l'autre en
  # développement, la résolution doit donc repartir de `Object` à chaque appel.
  class Observer
    def self.delivered_email(message)
      ::SentEmails::Recorder.record(message)
    rescue StandardError => e
      Rails.logger.error("[SentEmails::Observer] journalisation impossible : #{e.class} #{e.message}")
      Sentry.capture_exception(e) if defined?(Sentry)
      nil
    end
  end
end
