module Finance
  # Les filtres de la file « À affecter » (epic #288, phase 4).
  #
  # On ne classe pas dix mille lignes dans l'ordre où elles arrivent : on les
  # classe par lots qui se ressemblent — tout le bar, tout un compte, tout un
  # mois à clôturer, tous les petits montants. Ces filtres RESTREIGNENT
  # l'affichage, rien d'autre : ce qui est affectable ne change pas.
  #
  # Tout vit dans l'URL : une vue filtrée se partage, le bouton Précédent du
  # navigateur la retrouve, et un geste fait depuis la file relit les filtres
  # dans la page d'où il part (`Finance::UnallocatedQueue`).
  class QueueFilter
    SENS = { "in" => "Entrées", "out" => "Sorties" }.freeze
    KEYS = %i[q cash_account_id kind from to sens min max].freeze

    attr_reader :q, :account, :kind, :from, :to, :sens, :min_cents, :max_cents

    def initialize(params)
      params = (params || {}).to_h.with_indifferent_access
      @q = params[:q].to_s.strip.presence
      @account = CashAccount.find_by(id: params[:cash_account_id]) if params[:cash_account_id].present?
      @kind = params[:kind].presence if CashAccount::KINDS.include?(params[:kind])
      @from = parse_date(params[:from])
      @to = parse_date(params[:to])
      @sens = params[:sens].presence if SENS.key?(params[:sens])
      @min_cents = parse_cents(params[:min])
      @max_cents = parse_cents(params[:max])
    end

    def scope
      scope = CashEntry.pending.ordered
      scope = scope.matching(q) if q
      scope = scope.where(cash_account_id: account.id) if account
      scope = scope.where(cash_account_id: CashAccount.where(kind: kind).select(:id)) if kind
      scope = scope.where(entry_date: from..) if from
      scope = scope.where(entry_date: ..to) if to
      scope = sens == "in" ? scope.incoming : scope.outgoing if sens
      scope = scope.amount_between(min_cents, max_cents) if min_cents || max_cents
      scope
    end

    def active? = chips.any?

    # Les filtres actifs, un par pastille, chacun avec la clé à retirer de
    # l'URL pour l'enlever SEUL.
    def chips
      chips = []
      chips << { key: :q, label: "« #{q} »" } if q
      chips << { key: :cash_account_id, label: account.name } if account
      chips << { key: :kind, label: CashAccount::KIND_LABELS.fetch(kind, kind) } if kind
      chips << { key: :from, label: "Depuis le #{I18n.l(from, format: :short)}" } if from
      chips << { key: :to, label: "Jusqu'au #{I18n.l(to, format: :short)}" } if to
      chips << { key: :sens, label: SENS.fetch(sens) } if sens
      chips << { key: :min, label: "≥ #{euros(min_cents)}" } if min_cents
      chips << { key: :max, label: "≤ #{euros(max_cents)}" } if max_cents
      chips
    end

    # Les paramètres d'URL des filtres actifs, sans `except`.
    def to_params(except: nil)
      {
        q: q, cash_account_id: account&.id, kind: kind, from: from&.iso8601, to: to&.iso8601,
        sens: sens, min: min_cents && format_amount(min_cents), max: max_cents && format_amount(max_cents)
      }.compact.except(*Array(except))
    end

    private

    def parse_date(raw)
      raw.present? ? Date.parse(raw.to_s) : nil
    rescue Date::Error
      nil
    end

    # « 12,50 », « 12.50 » ou « 12 » ; le signe ne compte pas, la fourchette
    # se lit en valeur absolue.
    def parse_cents(raw)
      texte = raw.to_s.strip.delete(" ").tr(",", ".")
      return nil unless texte.match?(/\A-?\d+(\.\d{1,2})?\z/)

      (texte.to_d * 100).round.to_i.abs
    end

    def format_amount(cents) = format("%.2f", cents / 100.0).tr(".", ",")

    def euros(cents) = "#{format_amount(cents)} €"
  end
end
