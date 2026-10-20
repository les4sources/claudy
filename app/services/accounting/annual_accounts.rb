module Accounting
  # Le bilan et le compte de résultats d'un exercice, rangés selon le schéma
  # abrégé de la BNB (revue expert-comptable du 2026-10-20, manque n° 2 : « je
  # n'ai trouvé aucun bilan, aucun compte de résultats »).
  #
  # Une fondation ou une ASBL suit le schéma des associations et fondations
  # (fonds de la fondation, fonds affectés, dons et subsides en 73) ; une
  # société, celui des sociétés (apport, réserves). Seuls quelques libellés
  # changent : les rubriques et leurs codes BNB sont les mêmes.
  #
  # Chaque compte va dans UNE rubrique, déduite de son numéro PCMN. Les comptes
  # de tiers et de trésorerie (classes 4 et 5) vont du côté de leur solde : un
  # fournisseur débiteur devient une créance, une banque créditrice une dette
  # financière. C'est la règle du schéma, et c'est ce qui rend un 440000
  # débiteur visible au lieu de le noyer dans les dettes.
  #
  # Ce n'est pas le dépôt : pas d'annexe, pas de XBRL. C'est ce que le
  # comptable reprend dans son logiciel, et ce que le conseil lit.
  class AnnualAccounts
    Row = Data.define(:code, :label, :level, :kind, :amount_cents, :previous_cents, :accounts, :key) do
      def total? = kind == :total
      def section? = kind == :section
      def blank? = amount_cents.to_i.zero? && previous_cents.to_i.zero?
    end

    # Un nœud : [code BNB, libellé, clé de rubrique OU enfants, options].
    BALANCE_ASSETS = [
      ["20", "Frais d'établissement", :formation_expenses],
      ["21/28", "Actifs immobilisés", [
        ["21", "Immobilisations incorporelles", :intangible],
        ["22/27", "Immobilisations corporelles", [
          ["22", "Terrains et constructions", :land_buildings],
          ["23", "Installations, machines et outillage", :plant],
          ["24", "Mobilier et matériel roulant", :furniture],
          ["25", "Location-financement et droits similaires", :leasing],
          ["26", "Autres immobilisations corporelles", :other_tangible],
          ["27", "Immobilisations en cours et acomptes versés", :in_progress]
        ]],
        ["28", "Immobilisations financières", :financial_assets]
      ]],
      ["29/58", "Actifs circulants", [
        ["29", "Créances à plus d'un an", :long_term_receivables],
        ["3", "Stocks et commandes en cours d'exécution", :stocks],
        ["40/41", "Créances à un an au plus", [
          ["40", "Créances commerciales", :trade_receivables],
          ["41", "Autres créances", :other_receivables]
        ]],
        ["50/53", "Placements de trésorerie", :investments],
        ["54/58", "Valeurs disponibles", :cash],
        ["490/1", "Comptes de régularisation", :accrued_assets]
      ]]
    ].freeze

    def self.balance_liabilities(company)
      [
        ["10/15", company ? "Capitaux propres" : "Fonds propres", [
          ["10", company ? "Apport" : "Fonds de l'association ou de la fondation", :fund],
          ["12", "Plus-values de réévaluation", :revaluation],
          ["13", company ? "Réserves" : "Fonds affectés", :reserves],
          ["14", "Résultat reporté (+)/(−)", :retained],
          ["", "Résultat de l'exercice, pas encore affecté", :current_result],
          ["", "Résultats d'exercices antérieurs non affectés", :prior_unappropriated],
          ["15", "Subsides en capital", :capital_grants]
        ]],
        ["16", company ? "Provisions et impôts différés" : "Provisions pour risques et charges, dons et legs avec droit de reprise", :provisions],
        ["17/49", "Dettes", [
          ["17", "Dettes à plus d'un an", :long_term_debts],
          ["42/48", "Dettes à un an au plus", [
            ["42", "Dettes à plus d'un an échéant dans l'année", :current_portion],
            ["43", "Dettes financières", :financial_debts],
            ["44", "Dettes commerciales", :trade_debts],
            ["46", "Acomptes reçus sur commandes", :advances],
            ["45", "Dettes fiscales, salariales et sociales", :tax_social],
            ["47/48", "Autres dettes", :other_debts]
          ]],
          ["492/3", "Comptes de régularisation", :accrued_liabilities]
        ]]
      ]
    end

    INCOME_STATEMENT = [
      ["", "Produits et charges d'exploitation", :section],
      ["9900", "Marge brute d'exploitation (+)/(−)", [
        ["70", "Chiffre d'affaires", :turnover],
        ["71", "Variation des stocks et des commandes en cours (+)/(−)", :stock_variation],
        ["72", "Production immobilisée", :own_work],
        ["73", "Cotisations, dons, legs et subsides", :donations],
        ["74", "Autres produits d'exploitation", :other_operating_income],
        ["60", "Approvisionnements et marchandises", :supplies, :charge],
        ["61", "Services et biens divers", :services, :charge]
      ]],
      ["76A", "Produits d'exploitation non récurrents", :nonrecurring_operating_income],
      ["62", "Rémunérations, charges sociales et pensions", :remuneration, :charge],
      ["630", "Amortissements et réductions de valeur sur frais d'établissement, sur immobilisations incorporelles et corporelles", :depreciation, :charge],
      ["631/4", "Réductions de valeur sur stocks, commandes en cours et créances commerciales", :write_downs, :charge],
      ["635/8", "Provisions pour risques et charges", :provisions_charge, :charge],
      ["640/8", "Autres charges d'exploitation", :other_operating_charges, :charge],
      ["66A", "Charges d'exploitation non récurrentes", :nonrecurring_operating_charges, :charge],
      ["9901", "Bénéfice (perte) d'exploitation", :operating_result, :total],
      ["75/76B", "Produits financiers", [
        ["75", "Produits financiers récurrents", :financial_income],
        ["76B", "Produits financiers non récurrents", :nonrecurring_financial_income]
      ]],
      ["65/66B", "Charges financières", [
        ["65", "Charges financières récurrentes", :financial_charges, :charge],
        ["66B", "Charges financières non récurrentes", :nonrecurring_financial_charges, :charge]
      ], :charge],
      ["9903", "Bénéfice (perte) de l'exercice avant impôts", :result_before_taxes, :total],
      ["780/680", "Impôts différés : prélèvements (+) et transferts (−)", :deferred_taxes],
      ["67/77", "Impôts sur le résultat", :taxes, :charge],
      ["9904", "Bénéfice (perte) de l'exercice", :result, :total]
    ].freeze

    CHARGE_KEYS = %i[supplies services remuneration depreciation write_downs provisions_charge other_operating_charges
                     nonrecurring_operating_charges financial_charges nonrecurring_financial_charges taxes].freeze

    attr_reader :fiscal_year, :previous_year

    def initialize(fiscal_year)
      @fiscal_year = fiscal_year
      @entity = fiscal_year.legal_entity
      @previous_year = @entity.fiscal_years.where("ends_on < ?", fiscal_year.starts_on).order(ends_on: :desc).first
    end

    def company? = @entity.form != "foundation"
    def schema_label = company? ? "Schéma abrégé des sociétés" : "Schéma abrégé des associations et fondations"
    def provisional? = !@fiscal_year.closed?

    def assets = @assets ||= rows(BALANCE_ASSETS, :balance)
    def liabilities = @liabilities ||= rows(self.class.balance_liabilities(company?), :balance)

    def total_assets_cents = current.balance_total(:asset)
    def total_liabilities_cents = current.balance_total(:liability)
    def previous_total_assets_cents = previous&.balance_total(:asset)
    def previous_total_liabilities_cents = previous&.balance_total(:liability)
    def balanced? = total_assets_cents == total_liabilities_cents

    def income_statement = @income_statement ||= rows(INCOME_STATEMENT, :income)
    def result_cents = current.income(:result)
    def previous_result_cents = previous&.income(:result)

    # L'affectation : le résultat de l'exercice, ce qui était reporté avant, et
    # ce qui le sera après.
    def appropriation
      [
        Row.new("9905", "Résultat de l'exercice à affecter", 1, :line, current.income(:result), previous&.income(:result), [], nil),
        Row.new("14P", "Résultat reporté de l'exercice précédent", 1, :line, current.retained_before, previous&.retained_before, [], nil),
        Row.new("14", "Résultat à reporter", 0, :total, current.income(:result) + current.retained_before,
                previous && (previous.income(:result) + previous.retained_before), [], nil)
      ]
    end

    # Ce que le lecteur doit savoir avant de croire les chiffres.
    def warnings
      list = []
      list << "Exercice ouvert : ces comptes sont provisoires tant qu'il n'est pas clôturé." if provisional?
      pending = CashEntry.pending.in_period(@fiscal_year.starts_on, @fiscal_year.ends_on)
                         .joins(:cash_account).where(cash_accounts: { legal_entity_id: @entity.id }).count
      list << "#{pending} ligne(s) de trésorerie de l'exercice sont encore « à affecter »." if pending.positive?
      unless current.prior_unappropriated.zero?
        list << "Des exercices antérieurs ne sont pas clôturés : leurs résultats ne sont pas affectés (ligne à part dans les fonds propres)."
      end
      current.suspense.each do |account, cents|
        list << "Le compte d'attente #{account} n'est pas soldé (#{Money.new(cents, 'EUR').format})."
      end
      missing = FixedAsset.missing_depreciation(@fiscal_year)
      list << "Dotations aux amortissements pas encore passées pour #{missing.size} immobilisation(s)." if missing.any?
      list << "Le bilan ne balance pas : écart de #{Money.new(total_assets_cents - total_liabilities_cents, 'EUR').format}." unless balanced?
      list
    end

    private

    def current = @current ||= Figures.new(@fiscal_year)
    def previous = @previous ||= (@previous_year && Figures.new(@previous_year))

    # Un groupe additionne ses enfants directs. Au compte de résultats, une
    # charge s'y soustrait (la marge brute = produits − achats − services), et
    # un groupe de charges s'affiche en positif, comme ses lignes.
    def rows(tree, statement, level = 0)
      tree.flat_map do |code, label, content, kind|
        if content == :section || kind == :section
          [Row.new(code, label, level, :section, nil, nil, [], nil)]
        elsif content.is_a?(Array)
          children = rows(content, statement, level + 1)
          direct = children.select { |child| child.level == level + 1 && !child.section? }
          sign = kind == :charge ? -1 : 1
          [Row.new(code, label, level, :total, sign * signed_sum(direct, :amount_cents, statement),
                   previous && sign * signed_sum(direct, :previous_cents, statement), [], nil)] + children
        else
          [leaf(code, label, level, content, kind, statement)]
        end
      end
    end

    def signed_sum(rows, attribute, statement)
      rows.sum do |row|
        value = row.public_send(attribute).to_i
        statement == :income && CHARGE_KEYS.include?(row.key) ? -value : value
      end
    end

    CALCULATED = %i[current_result prior_unappropriated].freeze

    def leaf(code, label, level, key, kind, statement)
      if statement == :income
        total = kind == :total
        return Row.new(code, label, level, total ? :total : :line, current.income(key), previous&.income(key),
                       total ? [] : merge_accounts(current.income_accounts(key), previous&.income_accounts(key)), key)
      end

      details = CALCULATED.include?(key) ? [] : merge_accounts(current.balance_accounts(key), previous&.balance_accounts(key))
      Row.new(code, label, level, :line, current.balance(key), previous&.balance(key), details, key)
    end

    # [[compte, montant N, montant N-1]] : le détail d'une rubrique, pour que
    # le comptable retrouve d'où vient chaque chiffre.
    def merge_accounts(now, before)
      accounts = (now.keys + (before || {}).keys).uniq.sort_by(&:code)
      accounts.map { |account| [account, now[account], before&.[](account)] }
    end

    # Les chiffres d'UN exercice, rubrique par rubrique.
    class Figures
      def initialize(fiscal_year)
        @fiscal_year = fiscal_year
        @entity = fiscal_year.legal_entity
      end

      def balance(key) = balance_accounts(key).values.sum
      def balance_accounts(key) = balance_buckets.fetch(key, {})

      def balance_total(side)
        balance_buckets.select { |key, _| SIDE.fetch(key, :liability) == side }.values.sum { |accounts| accounts.values.sum }
      end

      def income(key)
        case key
        when :operating_result then operating_result
        when :result_before_taxes then operating_result + income(:financial_income) + income(:nonrecurring_financial_income) -
                                          income(:financial_charges) - income(:nonrecurring_financial_charges)
        when :result then income(:result_before_taxes) + income(:deferred_taxes) - income(:taxes)
        else income_accounts(key).values.sum
        end
      end

      def income_accounts(key) = income_buckets.fetch(key, {})

      def prior_unappropriated = balance(:prior_unappropriated)

      # Le résultat reporté AVANT l'affectation de l'exercice : le 14 de fin
      # d'exercice, moins ce que la clôture y a versé.
      def retained_before
        appropriation = JournalLine.joins(:journal_entry, :general_account)
                                   .where(journal_entries: { source_type: "FiscalYear", source_id: @fiscal_year.id, journal: "misc" })
                                   .where("general_accounts.code LIKE '14%'")
                                   .sum("journal_lines.credit_cents - journal_lines.debit_cents").to_i
        balance(:retained) - appropriation
      end

      def suspense
        accounts.filter_map do |id, account|
          cents = sums[id]
          [account, cents] if account.code.start_with?("499", "58") && !cents.zero?
        end
      end

      private

      SIDE = {
        formation_expenses: :asset, intangible: :asset, land_buildings: :asset, plant: :asset, furniture: :asset,
        leasing: :asset, other_tangible: :asset, in_progress: :asset, financial_assets: :asset,
        long_term_receivables: :asset, stocks: :asset, trade_receivables: :asset, other_receivables: :asset,
        investments: :asset, cash: :asset, accrued_assets: :asset
      }.freeze

      def operating_result
        %i[turnover stock_variation own_work donations other_operating_income nonrecurring_operating_income].sum { |key| income(key) } -
          %i[supplies services remuneration depreciation write_downs provisions_charge other_operating_charges
             nonrecurring_operating_charges].sum { |key| income(key) }
      end

      def sums = @sums ||= Balances.new(@entity).through(@fiscal_year.ends_on)

      def accounts
        @accounts ||= GeneralAccount.with_deleted { GeneralAccount.where(id: sums.keys).index_by(&:id) }
      end

      # { rubrique => { compte => montant positif du côté de la rubrique } }
      def balance_buckets
        @balance_buckets ||= begin
          buckets = Hash.new { |hash, key| hash[key] = Hash.new(0) }
          result = 0
          sums.each do |id, cents|
            account = accounts[id]
            next if account.nil?

            if account.klass >= 6
              result -= cents
              next
            end
            key = balance_key(account.code, cents)
            buckets[key][account] += SIDE.key?(key) ? cents : -cents
          end
          buckets[:current_result] = { result_account => result } unless result.zero?
          unless prior_unappropriated_cents.zero?
            buckets[:prior_unappropriated] = { prior_account => prior_unappropriated_cents }
          end
          buckets
        end
      end

      # Sans à-nouveau, les classes 1 à 5 cumulent tout l'historique, mais les
      # charges et produits des années passées n'y sont pas : s'ils n'ont pas
      # été affectés (exercices pas clôturés), le bilan ne balancerait pas. On
      # les montre à part plutôt que de les perdre.
      def prior_unappropriated_cents
        @prior_unappropriated_cents ||=
          if Balances.opening?(@fiscal_year)
            0
          else
            -JournalLine.joins(:journal_entry, :general_account)
                        .where(journal_entries: { legal_entity_id: @entity.id })
                        .where("journal_entries.entry_date < ?", @fiscal_year.starts_on)
                        .where(general_accounts: { klass: [6, 7] })
                        .sum("journal_lines.debit_cents - journal_lines.credit_cents").to_i
          end
      end

      # Des comptes fictifs pour porter une ligne calculée dans le détail.
      def result_account = GeneralAccount.new(code: "6/7", name: "Produits moins charges de l'exercice")
      def prior_account = GeneralAccount.new(code: "6/7", name: "Produits moins charges des exercices non clôturés")

      def balance_key(code, cents)
        case code[0]
        when "1" then equity_key(code)
        when "2" then fixed_asset_key(code)
        when "3" then :stocks
        when "4" then cents.positive? ? receivable_key(code) : payable_key(code)
        when "5" then cash_key(code, cents)
        else :other_debts
        end
      end

      def equity_key(code)
        case code[0, 2]
        when "10", "11" then :fund
        when "12" then :revaluation
        when "13" then :reserves
        when "14" then :retained
        when "15" then :capital_grants
        when "16" then :provisions
        else :long_term_debts
        end
      end

      def fixed_asset_key(code)
        { "20" => :formation_expenses, "21" => :intangible, "22" => :land_buildings, "23" => :plant, "24" => :furniture,
          "25" => :leasing, "26" => :other_tangible, "27" => :in_progress, "28" => :financial_assets,
          "29" => :long_term_receivables }.fetch(code[0, 2], :other_tangible)
      end

      def receivable_key(code)
        return :accrued_assets if code.start_with?("490", "491")

        code.start_with?("40") ? :trade_receivables : :other_receivables
      end

      def payable_key(code)
        return :accrued_liabilities if code.start_with?("492", "493")

        { "42" => :current_portion, "43" => :financial_debts, "44" => :trade_debts, "45" => :tax_social,
          "46" => :advances }.fetch(code[0, 2], :other_debts)
      end

      def cash_key(code, cents)
        return :financial_debts unless cents.positive?

        code[0, 2].to_i.between?(50, 53) ? :investments : :cash
      end

      # { rubrique => { compte => montant } } : produits au crédit, charges au
      # débit, en positif. L'affectation (69/79) n'est pas un produit ni une
      # charge : elle reste hors du compte de résultats.
      def income_buckets
        @income_buckets ||= begin
          buckets = Hash.new { |hash, key| hash[key] = Hash.new(0) }
          sums.each do |id, cents|
            account = accounts[id]
            next if account.nil? || account.klass < 6 || account.appropriation?

            key = income_key(account.code)
            buckets[key][account] += CHARGE_KEYS.include?(key) ? cents : -cents
          end
          buckets
        end
      end

      def income_key(code)
        three = code[0, 3].to_i
        case code[0, 2]
        when "60" then :supplies
        when "61" then :services
        when "62" then :remuneration
        when "63" then three == 630 ? :depreciation : (three <= 634 ? :write_downs : :provisions_charge)
        when "64" then :other_operating_charges
        when "65" then :financial_charges
        when "66" then three <= 664 ? :nonrecurring_operating_charges : :nonrecurring_financial_charges
        when "67", "77" then :taxes
        when "68", "78" then :deferred_taxes
        when "70" then :turnover
        when "71" then :stock_variation
        when "72" then :own_work
        when "73" then :donations
        when "74" then :other_operating_income
        when "75" then :financial_income
        when "76" then three <= 764 ? :nonrecurring_operating_income : :nonrecurring_financial_income
        else :other_operating_charges
        end
      end
    end
  end
end
