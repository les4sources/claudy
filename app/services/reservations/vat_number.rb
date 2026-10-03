module Reservations
  # Numéro de TVA saisi dans le funnel (étape Coordonnées, « Besoin d'une
  # facture ? » — Michael, 2026-10-03).
  #
  # Le client tape ce qu'il a sous les yeux : « BE 0123.456.789 », « 0123456789 »,
  # « fr 12 345678901 »… On le ramène à la forme compacte que lit VIES
  # (« BE0123456789 ») puis on contrôle le FORMAT du pays. Le numéro belge porte
  # en plus une clé de contrôle (modulo 97), vérifiée ici : une faute de frappe
  # est refusée avant même d'interroger VIES.
  #
  # Pays couverts : l'Union européenne (VIES), plus la Suisse et le Royaume-Uni,
  # que VIES ne connaît pas mais dont on accepte le format.
  module VatNumber
    PATTERNS = {
      "AT" => /\AU\d{8}\z/,
      "BE" => /\A[01]\d{9}\z/,
      "BG" => /\A\d{9,10}\z/,
      "CY" => /\A\d{8}[A-Z]\z/,
      "CZ" => /\A\d{8,10}\z/,
      "DE" => /\A\d{9}\z/,
      "DK" => /\A\d{8}\z/,
      "EE" => /\A\d{9}\z/,
      "EL" => /\A\d{9}\z/,
      "ES" => /\A[A-Z0-9]\d{7}[A-Z0-9]\z/,
      "FI" => /\A\d{8}\z/,
      "FR" => /\A[A-HJ-NP-Z0-9]{2}\d{9}\z/,
      "HR" => /\A\d{11}\z/,
      "HU" => /\A\d{8}\z/,
      "IE" => /\A(\d{7}[A-W][A-I]?|\d[A-Z+*]\d{5}[A-W])\z/,
      "IT" => /\A\d{11}\z/,
      "LT" => /\A(\d{9}|\d{12})\z/,
      "LU" => /\A\d{8}\z/,
      "LV" => /\A\d{11}\z/,
      "MT" => /\A\d{8}\z/,
      "NL" => /\A\d{9}B\d{2}\z/,
      "PL" => /\A\d{10}\z/,
      "PT" => /\A\d{9}\z/,
      "RO" => /\A\d{2,10}\z/,
      "SE" => /\A\d{12}\z/,
      "SI" => /\A\d{8}\z/,
      "SK" => /\A\d{10}\z/,
      "CH" => /\AE\d{9}(MWST|TVA|IVA)?\z/,
      "GB" => /\A(\d{9}|\d{12})\z/
    }.freeze

    # Pays que VIES sait contrôler (l'UE ; « EL » pour la Grèce).
    VIES_COUNTRIES = (PATTERNS.keys - %w[CH GB]).freeze

    module_function

    # « be 0123.456.789 » → « BE0123456789 ». Sans préfixe pays, on prend celui
    # de l'adresse de facturation (la Belgique par défaut). Un ancien numéro
    # belge à 9 chiffres reçoit son 0 de tête.
    def normalize(raw, country: "BE")
      compact = raw.to_s.upcase.gsub(/[^A-Z0-9+*]/, "")
      return nil if compact.empty?

      compact = "#{country_prefix(country)}#{compact}" if compact.match?(/\A\d/)
      compact = compact.sub(/\AGR/, "EL")
      compact = "BE0#{compact[2..]}" if compact.match?(/\ABE\d{9}\z/)
      compact
    end

    def valid?(vat)
      prefix, body = split(vat)
      pattern = PATTERNS[prefix]
      return false unless pattern && body.match?(pattern)
      return belgian_checksum?(body) if prefix == "BE"

      true
    end

    def vies_checkable?(vat)
      VIES_COUNTRIES.include?(split(vat).first)
    end

    def split(vat)
      vat = vat.to_s
      [vat[0, 2], vat[2..].to_s]
    end

    # Clé de contrôle belge : 97 − (8 premiers chiffres mod 97) = 2 derniers.
    def belgian_checksum?(body)
      97 - (body[0, 8].to_i % 97) == body[8, 2].to_i
    end

    def country_prefix(country)
      code = country.to_s.upcase.presence || "BE"
      code == "GR" ? "EL" : code
    end
  end
end
