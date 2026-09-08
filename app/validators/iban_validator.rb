# Valide un IBAN : longueur par pays, alphabet, et surtout la clé de contrôle
# mod 97 (ISO 13616). Un IBAN mal recopié est refusé à la saisie plutôt que
# découvert au retour du virement.
#
#   validates :iban, iban: true, allow_blank: true
#
# La validation attend un IBAN NORMALISÉ (sans espaces, en majuscules) : les
# modèles qui l'utilisent posent un `before_validation` qui s'en charge.
class IbanValidator < ActiveModel::EachValidator
  # Longueur totale de l'IBAN par code pays (registre SWIFT). La liste couvre
  # l'Europe où les 4 Sources virent ; un pays inconnu passe le contrôle de
  # format et la clé mod 97, mais pas le contrôle de longueur.
  LENGTHS = {
    "AD" => 24, "AT" => 20, "BE" => 16, "BG" => 22, "CH" => 21, "CY" => 28,
    "CZ" => 24, "DE" => 22, "DK" => 18, "EE" => 20, "ES" => 24, "FI" => 18,
    "FR" => 27, "GB" => 22, "GR" => 27, "HR" => 21, "HU" => 28, "IE" => 22,
    "IS" => 26, "IT" => 27, "LI" => 21, "LT" => 20, "LU" => 20, "LV" => 21,
    "MC" => 27, "MT" => 31, "NL" => 18, "NO" => 15, "PL" => 28, "PT" => 25,
    "RO" => 24, "SE" => 24, "SI" => 19, "SK" => 24, "SM" => 27
  }.freeze

  FORMAT = /\A[A-Z]{2}\d{2}[A-Z0-9]{10,30}\z/

  def validate_each(record, attribute, value)
    iban = value.to_s.gsub(/\s+/, "").upcase
    return if iban.blank?

    record.errors.add(attribute, message) unless valid_iban?(iban)
  end

  private

  def message = options.fetch(:message, "n'est pas un IBAN valide")

  def valid_iban?(iban)
    return false unless iban.match?(FORMAT)

    expected = LENGTHS[iban[0, 2]]
    return false if expected && iban.length != expected

    checksum(iban) == 1
  end

  # Mod 97 sur l'IBAN pivoté (les 4 premiers caractères passent à la fin), les
  # lettres remplacées par leur rang + 9 (A = 10 … Z = 35).
  def checksum(iban)
    rotated = iban[4..] + iban[0, 4]
    digits  = rotated.each_char.map { |c| c.match?(/\d/) ? c : (c.ord - 55).to_s }.join
    digits.to_i % 97
  end
end
