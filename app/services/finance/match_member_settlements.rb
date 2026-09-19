module Finance
  # Le rapprochement d'une ligne bancaire ENTRANTE avec le compte courant d'un
  # habitant (issue #349).
  #
  # Le geste inverse existe depuis l'epic #246 (`MatchMemberPayouts`) : payer un
  # cuisinier créditeur depuis une ligne sortante. Il manquait le miroir, et ça
  # se voyait — au 2026-09-19, 2 888 € de virements reçus n'avaient jamais été
  # encodés, dont 75 €/mois versés tous les mois depuis janvier. Les soldes
  # « À régler » affichaient des dettes déjà payées.
  #
  # **Ce service ne crée RIEN** (invariant B4, cf. l'en-tête de
  # `Finance::SuggestAllocations`) : il propose, il motive, un humain clique.
  #
  # Quatre indices, du plus sûr au moins sûr. La communication qui porte le code
  # du compte est une quasi-certitude — c'est la communication qu'on a soi-même
  # donnée à l'habitant. L'IBAN déjà vu sur ce compte vient juste après : il
  # désigne un compte en banque, pas une coïncidence. Le nom est un indice
  # humain, faillible. Le montant exact ne dit rien tout seul — deux ménages
  # peuvent devoir la même somme.
  #
  # SEULS LES COMPTES DÉBITEURS SONT PROPOSÉS. Un compte à zéro ou créditeur n'a
  # pas de dette en face : y imputer un virement le mettrait en faux crédit. Ça
  # borne du même coup les virements qui n'ont rien à faire au grand livre des
  # membres — épicerie, pain, cagnotte, pension d'animaux : sans charge en face,
  # pas de proposition.
  class MatchMemberSettlements
    Match = Struct.new(:member_account, :due_cents, :reason, :confidence, keyword_init: true)

    CONFIDENCE_CODE = 95
    CONFIDENCE_IBAN = 85
    CONFIDENCE_NAME = 70
    CONFIDENCE_AMOUNT = 60

    # Les mots trop courts ou trop communs ne font pas un indice de nom : « de »
    # ou « van » rapprocherait la moitié du village.
    NAME_STOPWORDS = %w[de des du la le les van der den und and mme mr sarl srl asbl].freeze
    MIN_NAME_TOKEN = 3
    EMPTY_SET = Set.new.freeze

    def initialize(accounts: nil)
      @accounts = accounts
    end

    # Les propositions pour une ligne de trésorerie, de la plus sûre à la moins.
    # Un compte n'apparaît qu'UNE fois, avec son meilleur indice : proposer deux
    # fois le même compte à deux confiances différentes n'aide personne à
    # décider.
    def for_entry(entry)
      return [] unless entry.amount_cents.positive?
      return [] if entry.cash_allocations.any?

      debtors.filter_map { |compte, du| match_for(entry, compte, du) }
             .sort_by { |match| [-match.confidence, match.member_account.name.to_s] }
    end

    # Une passe sur toute une page. Les soldes, les IBAN déjà vus et les noms des
    # ménages sont chargés UNE fois par instance, pas une fois par ligne : c'est
    # le rapprochement ligne à ligne qui avait fait tomber l'écran « À affecter »
    # à l'issue #202.
    def for_entries(entries)
      entries.each_with_object({}) do |entry, hash|
        matches = for_entry(entry)
        hash[entry.id] = matches if matches.any?
      end
    end

    private

    def match_for(entry, compte, du)
      if code_cite?(entry, compte)
        build(compte, du, "La communication porte le code du compte (#{compte.code})", CONFIDENCE_CODE)
      elsif iban_connu?(entry, compte)
        build(compte, du, "Cet IBAN a déjà servi à régler ce compte", CONFIDENCE_IBAN)
      elsif (nom = nom_reconnu(entry, compte))
        build(compte, du, "Le nom de la contrepartie ressemble à #{nom}", CONFIDENCE_NAME)
      elsif du == entry.amount_cents
        build(compte, du, "#{compte.name} doit exactement ce montant", CONFIDENCE_AMOUNT)
      end
    end

    def build(compte, du, reason, confidence)
      Match.new(member_account: compte, due_cents: du, reason: reason, confidence: confidence)
    end

    # La communication est saisie par l'habitant : elle arrive avec des espaces,
    # des tirets et une casse imprévisible. On compare sur la forme nue.
    def code_cite?(entry, compte)
      haystack = squeezed(entry.communication)
      return false if haystack.blank?

      haystack.include?(squeezed(compte.code))
    end

    def iban_connu?(entry, compte)
      iban = squeezed(entry.counterparty_iban)
      return false if iban.blank?

      known_ibans.fetch(compte.id, EMPTY_SET).include?(iban)
    end

    # Le nom du compte, ou celui d'un membre du ménage : un virement d'un ménage
    # part presque toujours du compte d'une seule des personnes qui y vivent.
    def nom_reconnu(entry, compte)
      contrepartie = normalized(entry.counterparty_name)
      return nil if contrepartie.blank?

      candidate_names(compte).find do |nom|
        tokens(nom).any? { |token| contrepartie.include?(token) }
      end
    end

    def candidate_names(compte)
      [compte.name, *household_names.fetch(compte.household_id, [])].compact_blank.uniq
    end

    # Les comptes DÉBITEURS et leur solde, en une seule requête groupée
    # (`MemberAccounts::Summary` fait le travail pour l'écran de liste). Sans ça,
    # calculer le solde de chaque compte pour chaque ligne de la page ferait
    # exploser le nombre de requêtes.
    def debtors
      @debtors ||= begin
        comptes = @accounts || MemberAccounts::Summary.new(MemberAccount.actives.ordered).accounts
        comptes.filter_map { |compte| [compte, compte.balance_cents] if compte.balance_cents.positive? }
      end
    end

    # Les IBAN déjà rapprochés sur chaque compte, par la trace que laisse
    # `RecordMemberSettlement` : une `CashAllocation` dont le document est le
    # compte. C'est la mémoire du dispositif — le deuxième virement d'un habitant
    # se reconnaît tout seul.
    def known_ibans
      @known_ibans ||= CashAllocation
                       .where(document_type: "MemberAccount", document_id: debtors.map { |compte, _| compte.id })
                       .joins(:cash_entry)
                       .where.not(cash_entries: { counterparty_iban: [nil, ""] })
                       .pluck(:document_id, Arel.sql("cash_entries.counterparty_iban"))
                       .each_with_object({}) do |(account_id, iban), hash|
                         (hash[account_id] ||= Set.new) << squeezed(iban)
                       end
    end

    # Les noms des membres des ménages concernés, chargés d'un coup.
    def household_names
      return @household_names if defined?(@household_names)

      ids = debtors.filter_map { |compte, _| compte.household_id }
      @household_names =
        if ids.empty?
          {}
        else
          HouseholdMember.where(household_id: ids).pluck(:household_id, :name)
                         .each_with_object({}) { |(id, nom), hash| (hash[id] ||= []) << nom }
        end
    end

    def tokens(nom)
      normalized(nom).split.reject { |mot| mot.length < MIN_NAME_TOKEN || NAME_STOPWORDS.include?(mot) }
    end

    # Sans accents ni ponctuation : « Bénédicte » et « BENEDICTE » sont la même
    # personne, et la banque ne garantit ni l'un ni l'autre.
    def normalized(texte)
      I18n.transliterate(texte.to_s).downcase.gsub(/[^a-z0-9]+/, " ").squish
    end

    def squeezed(texte) = texte.to_s.gsub(/[^A-Za-z0-9]+/, "").upcase
  end
end
