module MailIntake
  # La communication structurée belge (OGM / VCS) : +++123/4567/89002+++.
  #
  # Douze chiffres dont les deux derniers sont une clé de contrôle : les dix
  # premiers modulo 97, et 97 quand le reste est nul. Une communication dont la
  # clé est fausse n'est JAMAIS proposée : le virement partirait, mais le
  # fournisseur ne saurait pas le rapprocher, et la facture resterait impayée
  # chez lui.
  module StructuredCommunication
    PATTERN = %r{(?:\+{3}|\*{3})\s?(\d{3})\s?/\s?(\d{4})\s?/\s?(\d{5})\s?(?:\+{3}|\*{3})}

    module_function

    # Les communications valides d'un texte, normalisées, dans l'ordre.
    def scan(text)
      text.to_s.scan(PATTERN).map(&:join).select { |digits| valid_digits?(digits) }.map { |d| format(d) }.uniq
    end

    # « +++000/0024/11862+++ », « ***000/0024/11862*** » ou les 12 chiffres nus
    # → la forme normalisée, ou nil si ce n'est pas une communication valide.
    def normalize(raw)
      digits = raw.to_s.gsub(/\D/, "")
      digits.length == 12 && raw.to_s.gsub(/[\d\s+*\/]/, "").empty? && valid_digits?(digits) ? format(digits) : nil
    end

    def valid_digits?(digits)
      check = digits[0, 10].to_i % 97
      check = 97 if check.zero?
      check == digits[10, 2].to_i
    end

    def format(digits) = "+++#{digits[0, 3]}/#{digits[3, 4]}/#{digits[7, 5]}+++"
  end
end
