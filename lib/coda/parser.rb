# Parseur CODA — le format d'extrait de compte codé des banques belges (issue #181).
#
# Zéro dépendance, volontairement. La seule gem Ruby existante, `coda_standard`,
# est abandonnée depuis 2015 et ne couvre que CODA 2.2 ; le format est stable et
# documenté, le parseur tient en quelques centaines de lignes, et il vaut mieux
# qu'il soit notre problème plutôt qu'une dette dormante.
#
# **Les positions ne s'écrivent jamais de mémoire.** Chaque champ ci-dessous est
# recopié depuis la spécification Febelfin (standard CODA 2.7, annexe I), dont
# les tables sont reproduites dans `docs/coda-layout.md` avec le numéro de page.
# Une position décalée d'un caractère produit des montants faux qui ont l'air
# plausibles — le pire mode de panne possible pour de la comptabilité.
#
# Le parseur ne touche à aucun modèle : il rend des structures. C'est le service
# d'import qui décide quoi en faire, et c'est ce qui permet de le tester sur des
# fixtures sans base de données.
module Coda
  class ParseError < StandardError; end

  # Un mouvement : l'enregistrement 2.1 et ce que ses 2.2 / 2.3 / 3.1 ajoutent.
  Movement = Struct.new(
    :sequence, :detail, :bank_reference, :amount_cents, :value_date, :entry_date,
    :transaction_code, :communication, :structured?, :counterparty_account,
    :counterparty_name, :counterparty_bic, :customer_reference, :statement_sequence,
    keyword_init: true
  ) do
    # Le détail 0000 EST le mouvement ; les suivants sont la décomposition d'une
    # transaction globalisée, que l'enregistrement 9 ne totalise pas non plus.
    def main? = detail.zero?
  end

  Statement = Struct.new(
    :account_number, :currency, :account_name, :account_description,
    :sequence_number, :paper_sequence, :old_balance_cents, :old_balance_date,
    :new_balance_cents, :new_balance_date, :movements,
    keyword_init: true
  ) do
    def main_movements = movements.select(&:main?)
    def movements_total_cents = main_movements.sum(&:amount_cents)
    def balance_delta_cents = new_balance_cents - old_balance_cents
    def label = "#{account_number} n°#{sequence_number}"
  end

  File = Struct.new(:creation_date, :file_reference, :addressee, :bic,
                    :statements, :records_count, :debit_total_cents, :credit_total_cents,
                    keyword_init: true)

  class Parser
    RECORD_LENGTH = 128

    def self.call(content) = new(content).parse

    # Le CODA est un format à positions fixes en OCTETS. Le lire en UTF-8
    # ferait compter un caractère accentué pour un, alors qu'il en occupe deux :
    # toutes les positions suivantes glisseraient. On travaille donc en binaire
    # et on ne convertit qu'au moment d'extraire un texte.
    def initialize(content)
      @content = content.to_s.dup.force_encoding(Encoding::ASCII_8BIT)
    end

    def parse
      lines = @content.split(/\r?\n/).reject { |line| line.strip.empty? }
      raise ParseError, "Fichier vide — aucun enregistrement." if lines.empty?

      lines.each_with_index do |line, index|
        next if line.length == RECORD_LENGTH

        raise ParseError,
              "Enregistrement #{index + 1} : #{line.length} caractères au lieu de #{RECORD_LENGTH}. " \
              "Le fichier est tronqué ou n'est pas un CODA."
      end

      @file = nil
      @closed = false
      @statements = []
      @current = nil
      @movements = []
      @current_movement = nil

      lines.each_with_index do |line, index|
        if @closed
          raise ParseError,
                "Enregistrement #{index + 1} : il suit l'enregistrement de fin. Le fichier en contient " \
                "plusieurs concaténés — dépose-les séparément."
        end

        dispatch(line, index)
      end

      raise ParseError, "Fichier sans enregistrement d'en-tête (type 0)." if @file.nil?
      raise ParseError, "Fichier sans enregistrement de fin (type 9)." if @file.records_count.nil?

      close_statement
      @file.statements = @statements
      @file
    end

    private

    def dispatch(line, index)
      case line[0]
      when "0" then parse_header(line)
      when "1" then parse_old_balance(line)
      when "2" then parse_movement(line, index)
      when "3" then parse_information(line)
      # Enregistrement 4 : la communication LIBRE DU FICHIER (spec p. 29). Elle
      # suit l'enregistrement 8 et porte un texte de service de la banque, pas
      # une donnée de mouvement — les communications de mouvement arrivent par
      # les enregistrements 2.2, 2.3 et 3.1, qui sont bien lus. On ne l'importe
      # donc pas, et c'est un choix, pas un oubli.
      when "4" then nil
      when "8" then parse_new_balance(line)
      when "9" then parse_trailer(line)
      else
        raise ParseError, "Enregistrement #{index + 1} : type « #{line[0]} » inconnu."
      end
    end

    # --- Enregistrement 0 — en-tête (spec p. 15-16) ---
    def parse_header(line)
      raise ParseError, "Le fichier contient un second en-tête — dépose les fichiers séparément." if @file

      @file = File.new(
        creation_date: date_at(line, 6, 11),
        file_reference: at(line, 25, 34),
        addressee: at(line, 35, 60),
        bic: at(line, 61, 71),
        statements: []
      )
    end

    # --- Enregistrement 1 — ancien solde (spec p. 17-18) ---
    def parse_old_balance(line)
      close_statement

      account_zone = at(line, 6, 42)

      @current = Statement.new(
        account_number: account_zone[0, 34].to_s.strip,
        currency: account_zone[34, 3].to_s.strip,
        paper_sequence: at(line, 3, 5),
        old_balance_cents: signed_amount(line, sign_position: 43, from: 44, to: 58),
        old_balance_date: date_at(line, 59, 64),
        account_name: at(line, 65, 90),
        account_description: at(line, 91, 125),
        sequence_number: at(line, 126, 128),
        movements: []
      )
      @movements = []
    end

    # --- Enregistrements 2.1 / 2.2 / 2.3 — mouvement (spec p. 19-23) ---
    def parse_movement(line, index)
      raise ParseError, "Enregistrement #{index + 1} : mouvement hors de tout relevé." if @current.nil?

      case line[1]
      when "1" then start_movement(line)
      when "2" then complete_movement_2_2(line, index)
      when "3" then complete_movement_2_3(line, index)
      else
        raise ParseError, "Enregistrement #{index + 1} : code article « #{line[1]} » inconnu pour un type 2."
      end
    end

    def start_movement(line)
      structured = at(line, 62, 62) == "1"
      zone = at(line, 63, 115)

      @current_movement = Movement.new(
        sequence: number_at(line, 3, 6, "Numéro de séquence"),
        detail: number_at(line, 7, 10, "Numéro de détail"),
        bank_reference: at(line, 11, 31),
        amount_cents: signed_amount(line, sign_position: 32, from: 33, to: 47),
        value_date: date_at(line, 48, 53),
        transaction_code: at(line, 54, 61),
        # Communication structurée : le type occupe 63-65, la communication
        # elle-même commence en 66. La garder telle quelle, avec son type, est ce
        # qui permettra plus tard de reconnaître un OGM.
        communication: structured ? "#{zone[0, 3]} #{zone[3..]}".strip : zone,
        structured?: structured,
        entry_date: date_at(line, 116, 121),
        statement_sequence: at(line, 122, 124)
      )
      @movements << @current_movement
    end

    def complete_movement_2_2(line, index)
      movement = movement_for(line, index)
      movement.communication = [movement.communication, at(line, 11, 63)].join(" ").strip
      movement.customer_reference = at(line, 64, 98)
      movement.counterparty_bic = at(line, 99, 109)
    end

    def complete_movement_2_3(line, index)
      movement = movement_for(line, index)
      zone = at(line, 11, 47)
      movement.counterparty_account = zone[0, 34].to_s.strip
      movement.counterparty_name = at(line, 48, 82)
      suite = at(line, 83, 125)
      movement.communication = [movement.communication, suite].join(" ").strip if suite.present?
    end

    # --- Enregistrement 3.1 — information (spec p. 24-25) ---
    def parse_information(line)
      return if @current_movement.nil?
      return unless line[1] == "1"

      structured = at(line, 40, 40) == "1"
      zone = at(line, 41, 113)
      texte = structured ? "#{zone[0, 3]} #{zone[3..]}".strip : zone
      return if texte.blank?

      @current_movement.communication = [@current_movement.communication, texte].join(" ").strip
    end

    # --- Enregistrement 8 — nouveau solde (spec p. 28) ---
    def parse_new_balance(line)
      raise ParseError, "Enregistrement « nouveau solde » sans relevé ouvert." if @current.nil?

      @current.new_balance_cents = signed_amount(line, sign_position: 42, from: 43, to: 57)
      @current.new_balance_date = date_at(line, 58, 63)
    end

    # --- Enregistrement 9 — fin de fichier (spec p. 30) ---
    def parse_trailer(line)
      raise ParseError, "Enregistrement de fin sans en-tête." if @file.nil?

      @closed = true
      @file.records_count = at(line, 17, 22).to_i
      @file.debit_total_cents = amount(at(line, 23, 37))
      @file.credit_total_cents = amount(at(line, 38, 52))
    end

    def movement_for(line, index)
      sequence = number_at(line, 3, 6, "Numéro de séquence")
      detail = number_at(line, 7, 10, "Numéro de détail")
      found = @movements.find { |m| m.sequence == sequence && m.detail == detail }
      return found if found

      raise ParseError,
            "Enregistrement #{index + 1} : complément d'un mouvement (séquence #{sequence}, " \
            "détail #{detail}) qui n'existe pas."
    end

    def close_statement
      return if @current.nil?

      if @current.new_balance_cents.nil?
        raise ParseError, "Relevé #{@current.label} sans enregistrement « nouveau solde » (type 8)."
      end

      @current.movements = @movements
      @statements << @current
      @current = nil
      @current_movement = nil
      @movements = []
    end

    # Positions 1-indexées et inclusives, comme dans la spécification : les
    # traduire ici une bonne fois évite de les décaler de un partout ailleurs.
    def at(line, from, to)
      raw = line[(from - 1)..(to - 1)].to_s
      # Les banques belges émettent en ISO-8859-1 ; on convertit à l'extraction,
      # jamais avant, pour que le découpage reste juste.
      raw.dup.force_encoding(Encoding::ISO_8859_1).encode(Encoding::UTF_8, invalid: :replace,
                                                          undef: :replace, replace: "?").strip
    end

    # Un numéro de séquence ou de détail illisible deviendrait 0 avec `to_i` — et
    # 0, c'est justement le détail du mouvement principal. Une donnée douteuse
    # serait alors importée comme une vraie ligne.
    def number_at(line, from, to, label)
      raw = at(line, from, to)
      return raw.to_i if raw.match?(/\A\d+\z/)

      raise ParseError, "#{label} illisible : « #{raw} » (attendu des chiffres)."
    end

    def date_at(line, from, to)
      raw = line[(from - 1)..(to - 1)].to_s
      return nil if raw.blank? || raw == "000000"

      Date.strptime(raw, "%d%m%y")
    rescue Date::Error
      raise ParseError, "Date illisible : « #{raw} » (attendu JJMMAA)."
    end

    # 15 caractères = 12 entiers + 3 décimales. La troisième décimale est
    # toujours nulle en euros ; si elle ne l'est pas, on REFUSE plutôt que
    # d'arrondir — on n'invente pas un centime sur de l'argent réel.
    def amount(raw)
      digits = raw.to_s.strip
      raise ParseError, "Montant illisible : « #{raw} »." unless digits.match?(/\A\d+\z/)

      milli = digits.to_i
      unless (milli % 10).zero?
        raise ParseError,
              "Montant #{digits} : la troisième décimale n'est pas nulle. " \
              "Le parseur refuse d'arrondir un montant réel."
      end

      milli / 10
    end

    def signed_amount(line, sign_position:, from:, to:)
      cents = amount(at(line, from, to))
      sign = at(line, sign_position, sign_position)

      case sign
      when "0" then cents   # crédit — l'argent entre
      when "1" then -cents  # débit — l'argent sort
      else
        raise ParseError, "Signe « #{sign} » inconnu (attendu 0 = crédit, 1 = débit)."
      end
    end
  end
end
