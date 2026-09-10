require "digest"

module Coda
  # L'identité d'un mouvement bancaire, indépendante du fichier qui le porte.
  #
  # Le service d'import s'est longtemps appuyé sur le numéro de relevé et sur le
  # rang du mouvement dans le fichier. Les deux sont des propriétés de l'EXPORT,
  # pas du mouvement, et Triodos le démontre : son export « mutations » numérote
  # tous ses relevés `000` et renumérote ses mouvements à partir de 1 à chaque
  # téléchargement. Deux exports successifs se ressemblent donc trait pour trait
  # là où l'idempotence regardait, et diffèrent partout ailleurs. Résultat, le
  # second export entrait pour un doublon intégral du premier et se faisait
  # rejeter en bloc, silencieusement.
  #
  # L'empreinte ne retient donc que ce que la banque ne peut pas renuméroter :
  # les dates, le montant, la contrepartie, la communication et le code
  # opération. Ce sont les mêmes champs que ceux stockés sur `CashEntry`, ce qui
  # rend l'empreinte des lignes déjà importées recalculable sans le fichier
  # d'origine — c'est ce qui permet de reprendre l'existant.
  #
  # La référence bancaire (2.1, positions 11-31) aurait été la clé naturelle.
  # Elle est vide sur la totalité des mouvements des deux exports Triodos
  # réels ; s'y fier aurait produit une empreinte constante et fusionné tout le
  # relevé en une seule ligne.
  module Fingerprint
    SEPARATOR = "|".freeze

    # Deux mouvements réellement identiques le même jour existent : deux fois le
    # même loyer, deux retraits du même montant. Ils partagent leur empreinte de
    # base, et seul le rang d'occurrence les distingue. Sans lui, le second
    # serait pris pour un doublon du premier et disparaîtrait du journal.
    def self.call(occurrence: 1, **fields)
      format("%<digest>s:%<occurrence>02d", digest: digest(**fields), occurrence: occurrence)
    end

    def self.digest(entry_date:, value_date:, amount_cents:, counterparty_iban: nil,
                    counterparty_name: nil, communication: nil, transaction_code: nil)
      payload = [
        date(entry_date), date(value_date), amount_cents.to_i.to_s,
        code(counterparty_iban), text(counterparty_name), text(communication), text(transaction_code)
      ].join(SEPARATOR)

      Digest::SHA256.hexdigest(payload)[0, 32]
    end

    # Les champs arrivent tantôt du parseur, tantôt d'une colonne relue en base :
    # une `Date`, une `String` et un `nil` doivent produire le même octet, sans
    # quoi l'empreinte d'une ligne dépendrait du chemin par lequel on l'a lue.
    def self.date(value)
      return "" if value.blank?

      (value.respond_to?(:strftime) ? value : Date.parse(value.to_s)).strftime("%Y-%m-%d")
    rescue Date::Error
      value.to_s
    end

    def self.text(value) = value.to_s.gsub(/\s+/, " ").strip.upcase

    def self.code(value) = value.to_s.gsub(/[^A-Za-z0-9]/, "").upcase

    private_class_method :date, :text, :code
  end
end
