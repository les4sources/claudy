module Shop
  # Ventiler la « Caisse épicerie » d'un mois entre les trois carnets (epic #359,
  # décision 15).
  #
  # La caisse de l'épicerie n'a pas de compte à elle : on la vide régulièrement
  # dans la caisse du domaine, avec une ligne « Caisse épicerie ». Cet argent
  # mélange les trois carnets — épicerie, pain, artisanat. Les espèces que
  # chacun a déclarées (contrôle mensuel de l'Épicerie et de la Boulangerie,
  # relevés des artisans) donnent la clé de répartition : chaque ligne du mois
  # est proposée au prorata, sur les comptes de produit des carnets.
  #
  # **Rien ne se ventile tout seul** (invariant des services `Finance::*`) :
  # `proposals` se contente de montrer, et `apply!` n'est appelé que par un
  # humain qui a cliqué. Une ligne déjà comptabilisée est contre-passée puis
  # repassée, comme `Finance::UpdateCashLine` le fait pour une correction.
  class VentilateGroceryCash < ServiceBase
    class NotReady < StandardError; end
    class MonthClosed < StandardError; end

    # Le motif de la feuille de caisse sous lequel on saisit la vidange de la
    # caisse de l'épicerie (repointé sur 701002 en phase 1).
    MOTIF_LABEL = "Épicerie".freeze
    # Les lignes reprises de l'historique n'ont pas de motif : leur libellé
    # suffit à les reconnaître.
    LABEL_PATTERN = "caisse epicerie".freeze

    Part = Struct.new(:notebook, :account, :cents, keyword_init: true) do
      def label = ShopSetting::NOTEBOOK_LABELS.fetch(notebook)
    end

    Proposal = Struct.new(:entry, :parts, keyword_init: true) do
      # La ligne est-elle déjà rangée exactement comme proposé ?
      def applied?
        current = entry.cash_allocations.group(:general_account_id).sum(:amount_cents)
        wanted = parts.to_h { |part| [part.account.id, part.cents] }
        current == wanted
      end
    end

    def initialize(month:, whodunnit: nil)
      @month = month.beginning_of_month
      @whodunnit = whodunnit
      @settings = ShopSetting.current
    end

    # Les lignes « Caisse épicerie » de la caisse du domaine sur le mois.
    def lines
      @lines ||= begin
        scope = CashEntry.joins(:cash_account).where(cash_accounts: { kind: "cash" })
                         .incoming.in_period(@month, @month.end_of_month)
                         .where.not(status: "excluded")
        motif_ids = CashMotif.unscoped.where(label: MOTIF_LABEL).select(:id)
        scope.where(cash_motif_id: motif_ids).or(scope.matching(LABEL_PATTERN))
             .includes(:cash_allocations).order(:entry_date, :id).to_a
      end
    end

    def checks
      @checks ||= ShopMonthlyCheck.for_month(@month).index_by(&:channel)
    end

    # Les espèces déclarées par carnet : les deux contrôles mensuels, et la
    # somme des lignes « caisse » des relevés d'artisans du mois.
    def declared_cash
      @declared_cash ||= {
        grocery: checks["grocery"]&.cash_total_cents.to_i,
        bread: checks["bread"]&.cash_total_cents.to_i,
        craft: ConsignmentReport.for_month(@month).includes(:consignment_report_lines).to_a.sum(&:cash_declared_cents)
      }
    end

    def declared_total_cents = declared_cash.values.sum

    # Pourquoi on ne peut pas (encore) ventiler — nil quand tout est prêt.
    def blocker
      missing = ShopMonthlyCheck::CHANNELS.reject { |channel| checks[channel]&.validated? }
      if missing.any?
        labels = missing.map { |channel| ShopSetting::NOTEBOOK_LABELS.fetch(channel.to_sym) }
        return "Valide d'abord le contrôle #{labels.join(' et ')} : ses espèces font la clé de répartition."
      end
      return "Aucune espèce déclarée ce mois-ci : rien à répartir." if declared_total_cents.zero?

      account_missing = declared_cash.select { |notebook, cents| cents.positive? && account(notebook).nil? }.keys
      if account_missing.any?
        labels = account_missing.map { |notebook| ShopSetting::NOTEBOOK_LABELS.fetch(notebook) }
        return "Pas de compte de produit pour #{labels.join(', ')} : règle-le dans les réglages des carnets."
      end

      nil
    end

    def ready? = blocker.nil?

    def proposals
      return [] unless ready?

      lines.map { |entry| Proposal.new(entry: entry, parts: split(entry.amount_cents)) }
    end

    # Ventile toutes les lignes du mois qui ne le sont pas déjà. Retourne le
    # nombre de lignes réécrites.
    def apply!
      raise NotReady, blocker unless ready?
      if MonthClosing.closed?(@month)
        raise MonthClosed, "#{I18n.l(@month, format: '%B %Y')} est arrêté — sa caisse ne se réaffecte plus."
      end

      pending = proposals.reject(&:applied?)
      PaperTrail.request(whodunnit: @whodunnit || "shop_monthly_check") do
        ApplicationRecord.transaction { pending.each { |proposal| reallocate!(proposal) } }
      end
      pending.size
    end

    private

    def account(notebook) = @settings.revenue_account(notebook)

    # Le prorata au centime : chaque part prend sa part entière, et les
    # centimes qui restent vont aux plus gros restes — la somme des parts
    # retombe toujours exactement sur le montant de la ligne.
    def split(amount_cents)
      total = declared_total_cents
      shares = declared_cash.select { |_, cents| cents.positive? }.map do |notebook, cents|
        exact = Rational(amount_cents * cents, total)
        [notebook, exact.floor, exact - exact.floor]
      end
      leftover = amount_cents - shares.sum { |_, floor, _| floor }
      shares.sort_by { |_, _, rest| -rest }.each_with_index do |share, index|
        share[1] += 1 if index < leftover
      end

      ShopSetting::NOTEBOOKS.filter_map do |notebook|
        share = shares.find { |n, _, _| n == notebook }
        next if share.nil? || share[1].zero?

        Part.new(notebook: notebook, account: account(notebook), cents: share[1])
      end
    end

    # L'entité et le pôle restent ceux de la ligne : on change le compte de
    # produit, pas à qui appartient l'argent.
    def reallocate!(proposal)
      entry = proposal.entry
      previous = entry.cash_allocations.first
      entity_id = previous&.legal_entity_id || entry.cash_motif&.legal_entity_id || entry.cash_account.legal_entity_id
      team_id = previous&.team_id || entry.cash_motif&.team_id

      Accounting::UnpostCashEntry.new(cash_entry: entry, whodunnit: @whodunnit).run! if entry.posted?
      entry.cash_allocations.destroy_all
      proposal.parts.each do |part|
        entry.cash_allocations.create!(general_account: part.account, amount_cents: part.cents,
                                       legal_entity_id: entity_id, team_id: team_id,
                                       label: "Caisse épicerie — #{part.label}")
      end
      Accounting::PostCashEntry.new(cash_entry: entry.reload, whodunnit: @whodunnit).run!
    end
  end
end
