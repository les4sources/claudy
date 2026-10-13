module Finance
  # « Peut-on dépenser ? » (Michael, 2026-10-13) : la réponse franche, entité
  # par entité, à la question que la trésorerie seule ne tranche pas. Le solde
  # en banque n'est pas ce qu'on peut dépenser : une partie est déjà due, une
  # autre a été prêtée et devra être rendue.
  #
  #   marge = solde disponible
  #         + ce qui doit rentrer dans les 90 jours (séjours confirmés)
  #         − ce qui doit sortir dans les 90 jours (file « À payer », charges
  #           fixes, mensualités des dettes et litiges)
  #         − les dettes et litiges qui tombent au-delà
  #         − les prêts reçus encore dus
  #
  # La réserve est un mois de charges fixes : en dessous, on ne dépense pas
  # sans en parler. Le verdict ne cherche pas à rassurer : le point bas projeté
  # sous zéro suffit à dire non, même si la marge est positive.
  #
  # Ce que le verdict ne sait pas, il le dit (`reserves`) : des lignes « À
  # affecter » peuvent cacher un prêt ou une dette, un compte jamais vérifié
  # n'est pas dans le solde, un séjour en retard n'est pas une entrée certaine.
  class SpendingVerdict
    VERDICTS = %w[non prudence oui inconnu].freeze

    # Chaque entité qui a un compte de trésorerie, la Fondation d'abord.
    def self.for_all(today: Date.current, loans: Finance::Loans.new)
      LegalEntity.actives.where(id: CashAccount.where(active: true).select(:legal_entity_id))
                 .sort_by { |entity| [entity.form == "foundation" ? 0 : 1, entity.name] }
                 .map { |entity| new(legal_entity: entity, today: today, loans: loans) }
    end

    attr_reader :entity, :treasury

    def initialize(legal_entity:, today: Date.current, loans: Finance::Loans.new)
      @entity = legal_entity
      @treasury = Finance::Treasury.new(legal_entity: legal_entity, today: today)
      @loans = loans
    end

    def balance_cents = treasury.balance_cents
    def incoming_cents = treasury.incoming_cents
    def outgoing_cents = treasury.outgoing_cents
    def liabilities_later_cents = treasury.liabilities_beyond_horizon_cents

    def loans_cents
      @loans_cents ||= [@loans.groups.find { |group| group.entity == @entity }&.owed_cents.to_i, 0].max
    end

    # Un mois de charges fixes : la réserve en dessous de laquelle on ne
    # dépense pas sans en parler.
    def reserve_cents
      @reserve_cents ||= RecurringExpense.actives.where(legal_entity_id: @entity.id).sum(&:yearly_cents) / 12
    end

    def margin_cents
      balance_cents + incoming_cents - outgoing_cents - liabilities_later_cents - loans_cents
    end

    def lowest_point = treasury.lowest_point

    def verdict
      @verdict ||= if treasury.anchored_accounts.empty? then "inconnu"
                   elsif margin_cents.negative? || lowest_point.balance_cents.negative? then "non"
                   elsif margin_cents < reserve_cents then "prudence"
                   else "oui"
                   end
    end

    # Ce qu'on peut engager sans toucher à la réserve, quand le verdict est oui.
    def spendable_cents = verdict == "oui" ? margin_cents - reserve_cents : 0

    def headline
      case verdict
      when "non" then "Non : pas de dépense nouvelle."
      when "prudence" then "Avec prudence : seulement l'indispensable."
      when "oui" then "Oui, jusqu'à #{format_euros(spendable_cents)}."
      else "Impossible à dire : aucun solde vérifié."
      end
    end

    def reason
      case verdict
      when "non"
        if margin_cents.negative?
          "Ce qui est en banque est déjà dû : il manque #{format_euros(-margin_cents)} pour couvrir les dettes, les prêts et les 90 jours qui viennent."
        else
          "La marge est positive, mais la trésorerie passe sous zéro le #{I18n.l(lowest_point.date, format: :long)} " \
            "(#{format_euros(lowest_point.balance_cents)})."
        end
      when "prudence"
        "Il reste #{format_euros(margin_cents)} une fois tout payé, moins qu'un mois de charges fixes (#{format_euros(reserve_cents)})."
      when "oui"
        "Il reste #{format_euros(margin_cents)} une fois tout payé ; un mois de charges fixes (#{format_euros(reserve_cents)}) reste de côté."
      else
        "Aucun compte de #{@entity.name} n'a de solde vérifié (relevé CODA, export Beobank ou comptage de caisse)."
      end
    end

    # Ce que le verdict ne sait pas : dit en clair, jamais deviné.
    def reserves
      @reserves ||= [pending_reserve, *unanchored_reserves, late_reserve].compact
    end

    def pending_count = pending_scope.count
    def pending_net_cents = pending_scope.sum(:amount_cents)

    private

    def pending_scope
      CashEntry.pending.where(cash_account_id: treasury.accounts.map { |row| row.account.id })
    end

    def pending_reserve
      return if pending_count.zero?

      "#{pending_count} ligne(s) « À affecter » (#{format_euros(pending_net_cents)} nets) : tant qu'elles ne sont pas " \
        "affectées, un prêt ou une dette peut s'y cacher."
    end

    def unanchored_reserves
      treasury.unanchored_accounts.map do |row|
        "#{row.account.name} : #{format_euros(row.balance_cents)} selon les lignes, jamais vérifié, hors du solde."
      end
    end

    def late_reserve
      late = treasury.late_receivables
      return if late.empty?

      "#{late.size} séjour(s) passé(s) avec un reste dû (#{format_euros(late.sum(&:amount_cents))}) : pas compté, " \
        "un retard n'est pas une entrée certaine."
    end

    def format_euros(cents)
      ActiveSupport::NumberHelper.number_to_currency(cents / 100.0, unit: "€", precision: 0, format: "%n %u",
                                                                    delimiter: " ", separator: ",")
    end
  end
end
