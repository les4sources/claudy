module Finance
  # Le poste « charges » d'un compte membre, mois par mois (issue #354).
  #
  # La reprise comptable d'août 2026 a apparié les règlements aux charges dans
  # l'ordre, mois par mois. Pour deux foyers, l'appariement a glissé d'un cran :
  # leur virement de janvier avait été versé en décembre 2025 et la reprise l'a
  # attribué à la charge de décembre. La charge de janvier reste ouverte pour
  # toujours, et comme `MemberAccounts::Outstanding` impute la dette la plus
  # ancienne d'abord, le trou se propage sur toute l'année : chaque mois
  # apparaît partiellement impayé et la dernière ligne est coupée en son milieu.
  #
  # CE QUI DISTINGUE UN DÉCALAGE D'UNE DETTE : un décalage a un écart cumulé
  # CONSTANT — le même trou se décale de mois en mois sans jamais grandir.
  # Une vraie dette, elle, augmente le cumul à chaque mois impayé. C'est la
  # seule signature qui sépare les deux, et on ne peut pas la lire sur un solde
  # nu : il faut la suite des mois.
  #
  # L'écart cumulé démarre au REPORT des charges d'avant l'année auditée, sinon
  # une correction datée du 31 décembre — exactement le cas qu'on répare —
  # resterait invisible et le compte réparé continuerait d'être signalé. Au
  # dernier mois, ce cumul vaut `balance_cents` moins tout ce qui ne relève pas
  # des charges (solde d'ouverture compris).
  #
  # LECTURE SEULE. Rien n'est écrit, jamais : la correction est le travail de
  # `Finance::FixJanuaryOffset`, qui s'appuie sur ce calcul pour refuser
  # d'agir sur un compte qui n'a pas le symptôme.
  class MemberChargesAudit < ServiceBase
    FLOW = "charges".freeze

    # Trois mois : deux mois à l'identique arrivent sur un compte qui n'a rien
    # consommé ni rien versé, le troisième fait la différence entre le hasard et
    # une signature.
    RUN_LENGTH = 3

    Month = Struct.new(:starts_on, :billed_cents, :settled_cents, :cumulative_cents, keyword_init: true) do
      def delta_cents = billed_cents - settled_cents
      def label = starts_on.strftime("%Y-%m")
      def moved? = !billed_cents.zero? || !settled_cents.zero?
    end

    # Une suite de mois où le cumul ne bouge pas — la signature du décalage.
    Run = Struct.new(:amount_cents, :from, :to, keyword_init: true) do
      def length = (to.year * 12 + to.month) - (from.year * 12 + from.month) + 1
    end

    AccountAudit = Struct.new(:account, :year, :carried_cents, :months, :january_charges, keyword_init: true) do
      def cumulative_cents = months.last&.cumulative_cents || carried_cents

      # Le montant exact de la charge de janvier, lu au grand livre. Il n'est
      # JAMAIS passé en paramètre ni déduit d'une moyenne : une correction qui
      # s'écarte d'un centime du fait qu'elle répare crée un second écart.
      def january_charge_cents = january_charges.sum

      def single_january_charge? = january_charges.one?

      def offset_run
        return @offset_run if defined?(@offset_run)

        @offset_run = detect_run
      end

      def offset? = offset_run.present?

      private

      # Les mois APRÈS le dernier mouvement ne comptent pas : un cumul qui ne
      # bouge plus en novembre parce que rien n'a encore été encodé n'est pas
      # une signature, c'est une année inachevée.
      def observed
        last = months.rindex(&:moved?)
        last.nil? ? [] : months[0..last]
      end

      def detect_run
        best = nil
        observed.chunk_while { |a, b| a.cumulative_cents == b.cumulative_cents }.each do |chunk|
          next if chunk.first.cumulative_cents.zero?

          run = Run.new(amount_cents: chunk.first.cumulative_cents,
                        from: chunk.first.starts_on, to: chunk.last.starts_on)
          best = run if run.length >= RUN_LENGTH && (best.nil? || run.length > best.length)
        end
        best
      end
    end

    # `codes` restreint l'audit à quelques comptes (`ACCOUNT=SRC-0005`) ; sans
    # lui, tous les comptes actifs qui ont bougé sur le poste charges.
    def initialize(year: Date.current.year, codes: nil)
      @year = year.to_i
      @codes = Array(codes).map(&:to_s).map(&:strip).reject(&:empty?).presence
    end

    def run
      catch_error(context: { year: @year }) { audits }
    end

    def run! = audits

    # Un compte sans aucune charge sur l'année n'a pas de tableau : il n'y a
    # rien à lire, et une ligne de zéros par compte d'entité noierait les deux
    # foyers qu'on cherche.
    def audits
      @audits ||= accounts.filter_map { |account| build(account) }
    end

    def audit_for(account)
      audits.find { |audit| audit.account.id == account.id }
    end

    def flagged = audits.select(&:offset?)

    private

    def accounts
      scope = MemberAccount.actives.ordered
      scope = scope.where(code: @codes) if @codes
      scope.to_a
    end

    def build(account)
      entries = entries_by_account[account.id].to_a
      return nil if entries.empty?

      cumulative = carried_by_account.fetch(account.id, 0)
      months = (1..12).map do |number|
        starts_on = Date.new(@year, number, 1)
        month_entries = entries.select { |entry| entry.entry_date.month == number }
        month = Month.new(starts_on: starts_on,
                          billed_cents: month_entries.sum { |e| [e.amount_cents, 0].max },
                          settled_cents: month_entries.sum { |e| [-e.amount_cents, 0].max })
        cumulative += month.delta_cents
        month.cumulative_cents = cumulative
        month
      end

      january = entries.select { |entry| entry.entry_date.month == 1 && entry.amount_cents.positive? }
      AccountAudit.new(account: account, year: @year, months: months,
                       carried_cents: carried_by_account.fetch(account.id, 0),
                       january_charges: january.map(&:amount_cents))
    end

    def entries_by_account
      @entries_by_account ||= AccountEntry.where(member_account_id: accounts.map(&:id), flow: FLOW)
                                          .where(entry_date: Date.new(@year, 1, 1)..Date.new(@year, 12, 31))
                                          .order(:entry_date)
                                          .group_by(&:member_account_id)
    end

    # Le report des charges d'avant l'année. Le solde d'ouverture du compte n'en
    # fait pas partie : il ne porte aucun poste, et le ranger dans les charges
    # ferait mentir le cumul du dernier mois.
    def carried_by_account
      @carried_by_account ||= AccountEntry.where(member_account_id: accounts.map(&:id), flow: FLOW)
                                          .where(entry_date: ...Date.new(@year, 1, 1))
                                          .group(:member_account_id)
                                          .sum(:amount_cents)
    end
  end
end
