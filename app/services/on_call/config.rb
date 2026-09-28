module OnCall
  # Réglages de la ligne de garde. Les secrets Twilio vivent dans l'ENV, comme
  # ceux de Stripe (`.env` en local, `.hatchbox.env` en prod) ; l'heure de
  # bascule vit dans `settings`, modifiable depuis l'écran Ligne de garde.
  module Config
    HANDOVER_HOUR_KEY = "on_call.handover_hour".freeze
    DEFAULT_HANDOVER_HOUR = 7
    TIME_ZONE = "Europe/Brussels".freeze

    def self.handover_hour
      Setting.integer(HANDOVER_HOUR_KEY, default: DEFAULT_HANDOVER_HOUR).clamp(0, 23)
    end

    def self.account_sid = ENV["TWILIO_ACCOUNT_SID"].presence

    def self.auth_token = ENV["TWILIO_AUTH_TOKEN"].presence

    # Notre numéro +32 chez Twilio. Il sert de `callerId` à CHAQUE <Dial> :
    # Twilio facture la jambe sortante selon le caller ID (EEE ≈ 0,04 $/min
    # vers un mobile belge, US/CA ≈ 0,56 $/min).
    def self.twilio_phone_number = PhoneNumber.normalize(ENV["TWILIO_PHONE_NUMBER"])

    # Dernier recours quand ni le veilleur ni le suppléant ne décrochent.
    def self.fallback_number = PhoneNumber.normalize(ENV["TWILIO_FALLBACK_NUMBER"])
  end
end
