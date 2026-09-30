module MailIntake
  # Trouve dans le texte d'une facture les valeurs POSSIBLES : montants, dates,
  # numéros, numéros de TVA, IBAN (messagerie, phase 1).
  #
  # Les expressions sont réglées pour trop trouver plutôt que pas assez : Jev
  # choisit ensuite laquelle joue le rôle demandé (le total, l'échéance…), et
  # il ne peut choisir qu'une valeur qu'on lui a donnée. Une valeur absente
  # d'ici est une valeur que personne ne proposera.
  #
  # Chaque candidat garde sa forme brute (`raw`, ce qui est écrit dans le PDF,
  # et qui sert d'option à Jev) et sa forme normalisée (`value`).
  class InvoiceCandidates
    MAX_OPTIONS = 120

    MONTHS = {
      "janvier" => 1, "février" => 2, "fevrier" => 2, "mars" => 3, "avril" => 4, "mai" => 5, "juin" => 6,
      "juillet" => 7, "août" => 8, "aout" => 8, "septembre" => 9, "octobre" => 10, "novembre" => 11,
      "décembre" => 12, "decembre" => 12,
      "january" => 1, "february" => 2, "march" => 3, "april" => 4, "may" => 5, "june" => 6, "july" => 7,
      "august" => 8, "september" => 9, "october" => 10, "november" => 11, "december" => 12
    }.freeze

    SPACES = "[ \\u00A0\\u202F]".freeze
    # 1.234,56 · 1 234,56 · 84,12 · 1,234.56 · 84.12
    AMOUNT_RE = /(?<![\d.,])(?:\d{1,3}(?:(?:#{SPACES}|[.,])\d{3})+|\d+)[.,]\d{2}(?!\d|[.,]\d)/
    NUMERIC_DATE_RE = %r{(?<!\d)(\d{1,2})[/.-](\d{1,2})[/.-](\d{4}|\d{2})(?!\d)}
    ISO_DATE_RE = /(?<!\d)(\d{4})-(\d{2})-(\d{2})(?!\d)/
    TEXT_DATE_RE = /(?<!\d)(\d{1,2})(?:er)?\s+(#{MONTHS.keys.join('|')})\s+(\d{4})/i
    NUMBER_KEYWORD_RE = /(?:facture|invoice|factuur|rechnung|n°|nº|no\.|nr\.?|numéro|number|référence|reference|réf\.)/i
    NUMBER_TOKEN_RE = %r{[A-Za-z0-9][A-Za-z0-9\-/._]{1,28}[A-Za-z0-9]}
    VAT_RE = /\b(?:BE)?#{SPACES}?([01]\d{3}[.\s]?\d{3}[.\s]?\d{3}|\d{3}[.\s]?\d{3}[.\s]?\d{3})\b/
    IBAN_RE = /\b([A-Z]{2}\d{2}(?:#{SPACES}?[A-Z0-9]{4}){2,7}(?:#{SPACES}?[A-Z0-9]{1,4})?)\b/

    def self.normalize_vat(raw)
      digits = raw.to_s.gsub(/\D/, "")
      return nil if digits.length < 9

      digits.rjust(10, "0")[-10..]
    end

    def self.normalize_iban(raw) = raw.to_s.gsub(/\s/, "").upcase.presence

    def initialize(text)
      @text = text.to_s
    end

    def amounts
      uniq_by_raw(@text.scan(AMOUNT_RE).filter_map do |raw|
        cents = to_cents(raw)
        { raw: raw, value: cents } if cents&.positive?
      end)
    end

    def dates
      found = []
      @text.to_enum(:scan, NUMERIC_DATE_RE).each do
        m = Regexp.last_match
        year = m[3].length == 2 ? 2000 + m[3].to_i : m[3].to_i
        found << [m[0], safe_date(year, m[2].to_i, m[1].to_i)]
      end
      @text.to_enum(:scan, ISO_DATE_RE).each do
        m = Regexp.last_match
        found << [m[0], safe_date(m[1].to_i, m[2].to_i, m[3].to_i)]
      end
      @text.to_enum(:scan, TEXT_DATE_RE).each do
        m = Regexp.last_match
        found << [m[0], safe_date(m[3].to_i, MONTHS[m[2].downcase], m[1].to_i)]
      end
      uniq_by_raw(found.filter_map { |raw, date| { raw: raw, value: date } if plausible?(date) })
    end

    # Les jetons qui suivent un mot comme « facture » ou « n° », pourvu qu'ils
    # portent un chiffre et ne soient ni une date ni un montant.
    def numbers
      tokens = []
      @text.to_enum(:scan, NUMBER_KEYWORD_RE).each do
        window = @text[Regexp.last_match.end(0), 60].to_s
        window.scan(NUMBER_TOKEN_RE).first(3).each do |token|
          next unless token.match?(/\d/)
          next if token.match?(/\A#{AMOUNT_RE}\z/o) || token.match?(NUMERIC_DATE_RE) || token.match?(ISO_DATE_RE)

          tokens << { raw: token, value: token }
        end
      end
      uniq_by_raw(tokens)
    end

    def vat_numbers
      @text.scan(VAT_RE).flatten.filter_map { |raw| self.class.normalize_vat(raw) }.uniq
    end

    def ibans
      @text.scan(IBAN_RE).flatten.filter_map { |raw| self.class.normalize_iban(raw) }.uniq
    end

    private

    def uniq_by_raw(list)
      list.uniq { |c| c[:raw] }.first(MAX_OPTIONS)
    end

    # Le dernier séparateur suivi de deux chiffres est la virgule décimale ;
    # tout ce qui précède n'est que séparateur de milliers.
    def to_cents(raw)
      digits = raw.gsub(/#{SPACES}/o, "")
      integer, decimals = digits[0..-4], digits[-2..]
      (integer.gsub(/[.,]/, "").to_i * 100) + decimals.to_i
    rescue StandardError
      nil
    end

    def safe_date(year, month, day)
      Date.new(year, month, day)
    rescue ArgumentError, TypeError
      nil
    end

    def plausible?(date)
      date && date.year.between?(2015, Date.current.year + 2)
    end
  end
end
