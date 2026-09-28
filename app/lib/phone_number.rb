# Normalisation des numéros de téléphone au format E.164 (+32…). Une saisie
# locale (« 0470 12 34 56 ») est lue comme belge. Renvoie nil pour un numéro
# vide ou invalide : c'est à l'appelant de décider si c'est une erreur.
module PhoneNumber
  DEFAULT_COUNTRY = "BE".freeze

  def self.normalize(raw)
    return nil if raw.blank?

    parsed = Phonelib.parse(raw.to_s.strip, DEFAULT_COUNTRY)
    parsed.valid? ? parsed.e164 : nil
  end

  # « +32 470 12 34 56 » : lisible à l'écran, sans perdre l'indicatif.
  def self.display(e164)
    return nil if e164.blank?

    Phonelib.parse(e164).international.presence || e164
  end
end
