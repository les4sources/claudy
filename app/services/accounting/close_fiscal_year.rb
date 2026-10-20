module Accounting
  # La clôture annuelle d'un exercice (revue expert-comptable du 2026-10-20,
  # manque n° 1 : `FiscalYear#close!` ne faisait que poser un statut).
  #
  # Clôturer, c'est quatre gestes dans une transaction :
  #
  #   1. AFFECTER LE RÉSULTAT. Une opération diverse au dernier jour solde les
  #      classes 6 et 7 vers le résultat reporté : un bénéfice passe par 693
  #      (débit) vers 140 (crédit), une perte de 140 (débit) vers 793 (crédit).
  #      Après elle, charges et produits de l'exercice font zéro.
  #   2. VERROUILLER chaque écriture (`locked_at`) : le statut de l'exercice ne
  #      suffit plus seul à les protéger.
  #   3. CLÔTURER l'exercice.
  #   4. POSER L'À-NOUVEAU de l'exercice suivant, daté de son premier jour : les
  #      soldes des classes 1 à 5, compte par compte et tiers par tiers (un
  #      fournisseur reste un fournisseur d'une année à l'autre). L'exercice
  #      suivant est créé s'il n'existe pas.
  #
  # Pour l'à-nouveau, trois choix (`opening`) :
  #   * `generate` (défaut) : le poser, refusé si l'exercice suivant en a déjà un ;
  #   * `replace` : contre-passer celui qui existe (un à-nouveau repris d'un
  #     bilan Winbooks, par exemple), puis poser le calculé ;
  #   * `none` : ne rien poser — l'exercice suivant a déjà ses soldes d'ouverture
  #     par ailleurs (années reprises ligne à ligne).
  #
  # On clôture dans l'ordre : l'exercice précédent de l'entité doit l'être. Sans
  # ça, ses charges et produits n'ont pas été affectés, et des soldes cumulés
  # depuis l'origine ne balanceraient pas.
  class CloseFiscalYear < ServiceBase
    OPENING_MODES = %w[generate replace none].freeze
    OPENING_MODE_LABELS = {
      "generate" => "Poser l'à-nouveau",
      "replace" => "Remplacer l'à-nouveau existant",
      "none" => "Pas d'à-nouveau"
    }.freeze

    class Refused < ServiceError; end

    Line = Data.define(:account, :third_party, :cents) do
      def debit_cents = cents.positive? ? cents : 0
      def credit_cents = cents.negative? ? -cents : 0
    end

    Preview = Data.define(:fiscal_year, :result_cents, :appropriation, :next_year_label, :next_year_exists,
                          :existing_opening, :opening_lines, :warnings, :blockers) do
      def closable? = blockers.empty?
      def opening_debit_cents = opening_lines.sum(&:debit_cents)
      def opening_credit_cents = opening_lines.sum(&:credit_cents)
      def profit? = result_cents.positive?
    end

    attr_reader :fiscal_year, :opening

    def initialize(fiscal_year:, opening: "generate", whodunnit: nil)
      @fiscal_year = fiscal_year
      @entity = fiscal_year.legal_entity
      @opening = OPENING_MODES.include?(opening.to_s) ? opening.to_s : "generate"
      @whodunnit = whodunnit
    end

    def preview
      @preview ||= begin
        result = result_cents
        lines = opening_lines(pending_result_cents: result)
        Preview.new(
          fiscal_year: @fiscal_year,
          result_cents: result,
          appropriation: appropriation_lines(result),
          next_year_label: next_year_starts_on.year.to_s,
          next_year_exists: next_year.present?,
          existing_opening: next_year.present? && Balances.opening?(next_year),
          opening_lines: lines,
          warnings: warnings(lines),
          blockers: blockers(lines)
        )
      end
    end

    def run
      catch_error(context: { fiscal_year: @fiscal_year.id }) { close }
    end

    def run!
      close
    end

    private

    def close
      refused = preview.blockers.first
      raise Refused, refused if refused

      PaperTrail.request(whodunnit: @whodunnit || "accounting") do
        ApplicationRecord.transaction do
          @fiscal_year.lock!
          post_appropriation(preview.result_cents) unless preview.result_cents.zero?

          lines = opening_lines(pending_result_cents: 0)
          ecart = lines.sum(&:cents)
          raise Refused, unbalanced_message(ecart) unless ecart.zero? || @opening == "none"

          now = Time.current
          JournalEntry.where(fiscal_year_id: @fiscal_year.id, locked_at: nil).update_all(locked_at: now)
          @fiscal_year.update!(status: "closed", closed_at: now)

          post_opening(lines) unless @opening == "none"
          @fiscal_year
        end
      end
    end

    # Le résultat de l'exercice : produits moins charges, lus sur les écritures
    # de l'exercice lui-même. Une affectation déjà passée (puis contre-passée à
    # la réouverture) s'annule d'elle-même.
    def result_cents
      -JournalLine.joins(:journal_entry, :general_account)
                  .where(journal_entries: { fiscal_year_id: @fiscal_year.id })
                  .where(general_accounts: { klass: [6, 7] })
                  .sum("journal_lines.debit_cents - journal_lines.credit_cents").to_i
    end

    def appropriation_lines(result)
      return [] if result.zero?

      if result.positive?
        [Line.new(account: account(GeneralAccount::PROFIT_CARRIED_FORWARD_CODE), third_party: nil, cents: result),
         Line.new(account: account(GeneralAccount::RETAINED_EARNINGS_CODE), third_party: nil, cents: -result)]
      else
        [Line.new(account: account(GeneralAccount::RETAINED_EARNINGS_CODE), third_party: nil, cents: -result),
         Line.new(account: account(GeneralAccount::LOSS_CARRIED_FORWARD_CODE), third_party: nil, cents: result)]
      end
    end

    def post_appropriation(result)
      lines = appropriation_lines(result).map do |line|
        { account: ensure_account!(line.account), debit_cents: line.debit_cents, credit_cents: line.credit_cents,
          label: result.positive? ? "Bénéfice de l'exercice à reporter" : "Perte de l'exercice à reporter" }
      end
      PostDocument.new(legal_entity: @entity, journal: "misc", entry_date: @fiscal_year.ends_on,
                       label: "Affectation du résultat #{@fiscal_year.label}", lines: lines,
                       source: @fiscal_year, whodunnit: @whodunnit).run!
    end

    # Les soldes des classes 1 à 5 au dernier jour, compte par compte et tiers
    # par tiers. Avant que l'affectation soit passée (l'aperçu), le résultat
    # est ajouté au 140 pour montrer l'à-nouveau tel qu'il sera.
    def opening_lines(pending_result_cents:)
      sums = Balances.new(@entity).through(@fiscal_year.ends_on, by_third_party: true)
      accounts = GeneralAccount.with_deleted { GeneralAccount.where(id: sums.keys.map(&:first)).index_by(&:id) }
      third_parties = ThirdParty.where(id: sums.keys.map(&:last).compact).index_by(&:id)

      by_key = Hash.new(0)
      sums.each do |(account_id, third_party_id), cents|
        account = accounts[account_id]
        next if account.nil? || account.klass > 5

        by_key[[account, third_parties[third_party_id]]] += cents
      end
      by_key[[account(GeneralAccount::RETAINED_EARNINGS_CODE), nil]] -= pending_result_cents unless pending_result_cents.zero?

      by_key.reject { |_, cents| cents.zero? }
            .map { |(account, third_party), cents| Line.new(account: account, third_party: third_party, cents: cents) }
            .sort_by { |line| [line.account.code, line.third_party&.name.to_s] }
    end

    def post_opening(lines)
      target = next_year || create_next_year!
      reverse_existing_opening(target) if @opening == "replace"
      return if lines.empty?

      PostDocument.new(
        legal_entity: @entity, journal: "opening", entry_date: target.starts_on,
        label: "À-nouveau #{target.label} (clôture #{@fiscal_year.label})",
        source: @fiscal_year, whodunnit: @whodunnit,
        lines: lines.map do |line|
          { account: ensure_account!(line.account), third_party: line.third_party,
            debit_cents: line.debit_cents, credit_cents: line.credit_cents, label: "À-nouveau" }
        end
      ).run!
    end

    # Contre-passé à sa propre date, comme le fait l'API d'ouverture : il
    # disparaît du solde de l'exercice sans quitter le journal.
    def reverse_existing_opening(target)
      Balances.opening_entries(target).find_each do |entry|
        ReverseEntry.new(journal_entry: entry, entry_date: entry.entry_date, whodunnit: @whodunnit,
                         label: "Contre-passation — #{entry.label} (remplacé à la clôture #{@fiscal_year.label})").run!
      end
    end

    def warnings(lines)
      list = []
      pending = CashEntry.pending.in_period(@fiscal_year.starts_on, @fiscal_year.ends_on)
                         .joins(:cash_account).where(cash_accounts: { legal_entity_id: @entity.id }).count
      if pending.positive?
        list << "#{pending} ligne(s) de trésorerie de l'exercice sont encore « à affecter » : le résultat ne les compte pas."
      end
      missing = FixedAsset.missing_depreciation(@fiscal_year)
      if missing.any?
        list << "Dotations aux amortissements non passées pour #{missing.size} immobilisation(s) " \
                "(#{missing.first(3).map(&:name).join(', ')}#{'…' if missing.size > 3})."
      end
      lines.select { |line| line.account.code.start_with?("499", "58") }.each do |line|
        list << "Le compte #{line.account} n'est pas soldé (#{Money.new(line.cents, 'EUR').format}) : il passera tel quel dans l'à-nouveau."
      end
      if @opening == "replace" && preview_existing_opening?
        list << "L'à-nouveau existant de #{next_year.label} sera contre-passé puis remplacé par celui-ci."
      end
      list
    end

    def blockers(lines)
      list = []
      list << "L'exercice #{@fiscal_year.label} est déjà clôturé." if @fiscal_year.closed?
      if previous_year && !previous_year.closed?
        list << "Clôture d'abord l'exercice #{previous_year.label} de #{@entity.name} : on clôture dans l'ordre."
      end
      unless @opening == "none"
        if next_year&.closed?
          list << "L'exercice #{next_year.label} est clôturé : on n'y pose plus d'à-nouveau."
        elsif @opening == "generate" && preview_existing_opening?
          list << "L'exercice #{next_year.label} a déjà un à-nouveau. Choisis « remplacer » pour le contre-passer " \
                  "et poser celui-ci, ou « aucun » pour le garder."
        end
        ecart = lines.sum(&:cents)
        list << unbalanced_message(ecart) unless ecart.zero?
      end
      list
    end

    def preview_existing_opening? = next_year.present? && Balances.opening?(next_year)

    def unbalanced_message(ecart)
      "L'à-nouveau ne balance pas (écart de #{Money.new(ecart, 'EUR').format}) : des soldes des années antérieures " \
        "ne sont pas affectés. Vérifie la balance de l'exercice avant de clôturer."
    end

    def previous_year
      @previous_year ||= @entity.fiscal_years.where("ends_on < ?", @fiscal_year.starts_on).order(ends_on: :desc).first
    end

    def next_year_starts_on = @fiscal_year.ends_on + 1

    def next_year
      return @next_year if defined?(@next_year)

      @next_year = @entity.fiscal_years.find_by(starts_on: next_year_starts_on)
    end

    def create_next_year!
      # Par l'association : `fiscal_year_for`, qui range chaque écriture, lit
      # les exercices déjà chargés et ne verrait pas un exercice créé à côté.
      @next_year = @entity.fiscal_years.create!(starts_on: next_year_starts_on,
                                                ends_on: next_year_starts_on.next_year - 1, status: "open")
    end

    ACCOUNT_NAMES = {
      GeneralAccount::RETAINED_EARNINGS_CODE => "Résultat reporté",
      GeneralAccount::PROFIT_CARRIED_FORWARD_CODE => "Bénéfice à reporter",
      GeneralAccount::LOSS_CARRIED_FORWARD_CODE => "Perte à reporter"
    }.freeze

    # Les comptes d'affectation manquent au plan repris de Winbooks : l'aperçu
    # montre un compte pas encore enregistré, la clôture le crée.
    def account(code)
      @accounts ||= {}
      @accounts[code] ||= GeneralAccount.with_deleted { GeneralAccount.find_by(code: code) } ||
                          GeneralAccount.new(code: code, name: ACCOUNT_NAMES.fetch(code))
    end

    def ensure_account!(account)
      account.save! if account.new_record?
      account
    end
  end
end
