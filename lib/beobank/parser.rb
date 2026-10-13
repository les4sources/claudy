require "bigdecimal"
require Rails.root.join("lib/xlsx/reader")

# Parseur de l'export Excel de Beobank — « Vos comptes », une feuille par
# compte (Michael, 2026-10-13).
#
# Beobank ne propose pas d'export CODA à la SRL Domaine d'Ahinvaux : son seul
# export utilisable est ce classeur. Une feuille de compte a cette forme :
#
#   ligne 1   Situation de votre compte … au 13/10/2026
#   ligne 2   IBAN : BE63 9502 6523 4408
#   ligne 3   Solde initial : (une formule SANS valeur calculée)
#   ligne 5   Date | Valeur | Libellé | Débit | Crédit | Solde | Dev
#   …         un mouvement par ligne ; débit négatif, crédit positif
#   fin       Solde au 13/10/2026 : 987,40
#
# Le solde initial n'est qu'une formule (`=F301-SUM(D)-SUM(E)`) que l'export
# n'a jamais calculée : on le déduit donc du solde final, ce qui ne prouve rien
# à lui seul. Le contrôle réel est la colonne Solde, que Beobank remplit : le
# cumul des montants lus doit y retomber jour après jour (`build_statement`).
# C'est ce qui attrape un montant mal lu.
#
# Comme le parseur CODA, il ne touche à aucun modèle : il rend des structures.
module Beobank
  class ParseError < StandardError; end

  Movement = Struct.new(:row, :entry_date, :value_date, :label, :amount_cents, :balance_cents,
                        keyword_init: true)

  Statement = Struct.new(:sheet_name, :iban, :account_name, :old_balance_cents, :new_balance_cents,
                         :new_balance_date, :movements, keyword_init: true) do
    def movements_total_cents = movements.sum(&:amount_cents)
    def balance_delta_cents = new_balance_cents - old_balance_cents
    def old_balance_date = movements.map(&:entry_date).min
    def label = "Beobank #{iban}"
  end

  Export = Struct.new(:export_date, :statements, keyword_init: true)

  class Parser
    HEADERS = %w[DATE VALEUR LIBELLE DEBIT CREDIT].freeze

    def self.call(content) = new(content).parse

    def initialize(content)
      @content = content
    end

    def parse
      sheets = Xlsx::Reader.call(@content)
      statements = sheets.reject(&:hidden).filter_map { |sheet| statement(sheet) }
      if statements.empty?
        raise ParseError, "Aucune feuille de compte trouvée (colonnes Date, Valeur, Libellé, Débit, Crédit). " \
                          "Ce classeur n'est pas un export Beobank des mouvements."
      end

      Export.new(export_date: statements.filter_map(&:new_balance_date).max, statements: statements)
    rescue Xlsx::ReadError => e
      raise ParseError, e.message
    end

    private

    def statement(sheet)
      header_row, = sheet.rows.find { |_, cells| header?(cells) }
      return nil if header_row.nil?

      iban = find_iban(sheet, header_row)
      raise ParseError, "Feuille « #{sheet.name} » : l'IBAN du compte est introuvable." if iban.nil?

      movements = []
      closing = nil
      sheet.rows.sort.each do |number, cells|
        next if number <= header_row

        if (solde = closing_balance(cells))
          closing = solde
          break
        end

        movement = movement(sheet, number, cells)
        movements << movement if movement
      end

      if closing.nil?
        raise ParseError, "Feuille « #{sheet.name} » : la ligne « Solde au … » est introuvable. " \
                          "L'export est tronqué."
      end

      build_statement(sheet, iban, movements, *closing)
    end

    def header?(cells) = cells.first(5).map { |cell| normalize_header(cell) } == HEADERS

    def normalize_header(cell)
      cell.to_s.unicode_normalize(:nfkd).gsub(/\p{Mn}/, "").strip.upcase
    end

    # « IBAN : BE63 9502 6523 4408 », quelque part au-dessus des en-têtes.
    def find_iban(sheet, header_row)
      sheet.rows.each do |number, cells|
        break if number >= header_row

        cells.compact.each do |cell|
          match = cell.to_s.match(/IBAN\s*:\s*([A-Z]{2}[0-9A-Z ]{10,40})/i)
          return match[1].gsub(/\s+/, "").upcase if match
        end
      end
      nil
    end

    def account_name(sheet)
      titre = sheet.rows.values.first&.compact&.first.to_s
      titre[/Situation de votre compte (.+?) \(/, 1] || sheet.name
    end

    # [solde, date] si la ligne est « Solde au 13/10/2026 : 987,40 ».
    def closing_balance(cells)
      index = cells.index { |cell| cell.is_a?(String) && cell.strip.match?(/\ASolde au /i) }
      return nil if index.nil?

      date = Xlsx::Reader.date(cells[index][%r{\d{2}/\d{2}/\d{4}}])
      montant = cells[(index + 1)..].find { |cell| cell.is_a?(Numeric) }
      raise ParseError, "La ligne « #{cells[index].strip} » ne porte pas de montant." if montant.nil?

      [cents(montant), date]
    end

    def movement(sheet, number, cells)
      date, valeur, libelle, debit, credit, solde = cells
      return nil if date.nil? && libelle.nil? && debit.nil? && credit.nil?

      entry_date = Xlsx::Reader.date(date)
      raise ParseError, "Feuille « #{sheet.name} », ligne #{number} : date illisible (#{date.inspect})." if entry_date.nil?
      unless [debit, credit].compact.size == 1 && [debit, credit].compact.all?(Numeric)
        raise ParseError, "Feuille « #{sheet.name} », ligne #{number} : il faut un montant, au débit OU au crédit."
      end

      Movement.new(row: number, entry_date: entry_date, value_date: Xlsx::Reader.date(valeur),
                   label: libelle.to_s.unicode_normalize(:nfc).gsub(/\s+/, " ").strip,
                   amount_cents: cents(debit || credit),
                   balance_cents: solde.is_a?(Numeric) ? cents(solde) : nil)
    end

    # Beobank n'affiche pas le solde dans l'ordre de ses lignes : au sein d'une
    # même journée, une ligne peut porter le solde de fin de journée et la
    # suivante un solde intermédiaire. Le contrôle se fait donc par JOUR : le
    # cumul des montants lus à la fin de chaque journée doit figurer parmi les
    # soldes que Beobank affiche ce jour-là. Un montant mal lu décale le cumul
    # de toutes les journées suivantes, et le contrôle le voit.
    def build_statement(sheet, iban, movements, closing_cents, closing_date)
      opening = closing_cents - movements.sum(&:amount_cents)

      solde = opening
      movements.group_by(&:entry_date).sort.each do |date, du_jour|
        solde += du_jour.sum(&:amount_cents)
        affiches = du_jour.filter_map(&:balance_cents)
        next if affiches.empty? || affiches.include?(solde)

        raise ParseError,
              "Feuille « #{sheet.name} », #{date.strftime('%d/%m/%Y')} : le cumul des montants lus " \
              "(#{format_cents(solde)}) ne correspond à aucun solde affiché par Beobank ce jour-là " \
              "(#{affiches.map { |c| format_cents(c) }.join(', ')}). Rien n'a été importé."
      end

      Statement.new(sheet_name: sheet.name, iban: iban, account_name: account_name(sheet),
                    old_balance_cents: opening, new_balance_cents: closing_cents,
                    new_balance_date: closing_date, movements: movements)
    end

    def cents(value) = (BigDecimal(value.to_s) * 100).round.to_i

    def format_cents(cents) = format("%.2f €", cents / 100.0).tr(".", ",")
  end
end
