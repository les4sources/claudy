module Finance
  # La trésorerie de la Fondation : ce qu'on a, ce qui doit rentrer, ce qui doit
  # sortir — et la courbe qui relie les trois.
  #
  # Objet de lecture, comme `CashSheet` : aucune écriture, aucun état. Trois
  # règles le tiennent, et chacune répond à une façon précise de mentir.
  #
  # 1. UN SOLDE N'ENTRE DANS LE TOTAL QUE S'IL EST ANCRÉ. La somme des lignes
  #    d'un compte n'est son solde que si les lignes sont complètes. La banque
  #    l'est : chaque relevé CODA porte le solde que Triodos affiche, et on cale
  #    la courbe dessus. La caisse ne l'est qu'après un comptage validé — sur la
  #    copie de prod de septembre 2026, ses lignes cumulent 16 300 € alors
  #    qu'elle n'a jamais été comptée. Un compte sans ancre reste affiché, à part,
  #    avec son solde théorique : le cacher effacerait la question, l'additionner
  #    fausserait tout le reste.
  #
  # 2. UNE SEULE VÉRITÉ PAR MONTANT. Le reste dû d'un séjour vient de
  #    `Stays::IndexAmounts` (miroir en lot de `Stay#balance_due_cents`), ce qui
  #    doit sortir vient de `Finance::PayableQueue` (la file « À payer »). Un
  #    calcul parallèle finirait par diverger sans que personne le voie.
  #
  # 3. LA PROJECTION EST PRUDENTE. Elle part du solde d'aujourd'hui, ajoute le
  #    reste dû des séjours confirmés à leur date d'arrivée (décision de Michael
  #    du 2026-09-29) et retire les dettes à leur échéance — une dette échue ou
  #    sans échéance sort aujourd'hui. Un séjour passé non soldé depuis moins
  #    d'un an est encore à encaisser (Michael, 2026-10-18) : il entre
  #    aujourd'hui, comme une dette échue sort aujourd'hui. Au-delà d'un an, il
  #    va « à assainir » et n'entre pas.
  #    Les charges fixes (`RecurringExpense`, 2026-09-30) sortent à chaque
  #    occurrence, sauf quand une vraie facture du même tiers couvre la période.
  class Treasury
    HISTORY_MONTHS = 12
    HORIZON_DAYS = 90
    # Au-delà d'un an après le départ, un reste dû est bien plus souvent un
    # paiement jamais relié au séjour qu'une vraie créance : il va dans le bloc
    # « à assainir », pas dans ce qui doit rentrer.
    STALE_AFTER_DAYS = 365

    Anchor = Struct.new(:date, :balance_cents, :source, keyword_init: true)

    AccountBalance = Struct.new(:account, :balance_cents, :as_of, :anchor, keyword_init: true) do
      def anchored? = anchor.present?
    end

    # Un point de la courbe. Un point projeté porte les mouvements de son jour
    # (`movements`) : c'est ce que le graphique montre au survol.
    Point = Struct.new(:date, :balance_cents, :projected, :movements, keyword_init: true) do
      def movements = self[:movements] || []
    end

    # Un mouvement attendu, signé : positif s'il rentre, négatif s'il sort.
    Movement = Struct.new(:date, :label, :amount_cents, keyword_init: true)

    Receivable = Struct.new(:stay, :due_on, :amount_cents, keyword_init: true)

    # Une sortie attendue : une dette de la file « À payer » (`payable`), une
    # occurrence de charge fixe (`recurring_expense`) ou une mensualité d'une
    # dette ou d'un litige sans facture (`liability`) — une seule des trois.
    Outflow = Struct.new(:payable, :recurring_expense, :liability, :due_on, :amount_cents, keyword_init: true) do
      def recurring? = recurring_expense.present?
      def liability? = liability.present?
    end

    def self.for_foundation(today: Date.current)
      entity = LegalEntity.actives.find_by(form: "foundation")
      entity && new(legal_entity: entity, today: today)
    end

    def initialize(legal_entity:, today: Date.current)
      @entity = legal_entity
      @today = today
    end

    attr_reader :today

    def horizon_end = @today + HORIZON_DAYS
    def history_start = (@today - HISTORY_MONTHS.months).beginning_of_month

    # --- Ce qu'on a --------------------------------------------------------

    # Chaque compte qui a au moins une ligne ou une ancre. Un compte Stripe
    # « par versement » n'a pas de ligne à lui — son argent apparaît sur la
    # banque au versement — et disparaît donc naturellement d'ici.
    def accounts
      @accounts ||= cash_accounts.filter_map do |account|
        anchor = anchor_for(account)
        next if movements[account.id].empty? && anchor.nil?

        AccountBalance.new(account: account, anchor: anchor,
                           balance_cents: balance_at(account, @today),
                           as_of: [movements[account.id].keys.max, anchor&.date].compact.max)
      end
    end

    def anchored_accounts = accounts.select(&:anchored?)
    def unanchored_accounts = accounts.reject(&:anchored?)

    def balance_cents = anchored_accounts.sum(&:balance_cents)

    # La date la plus ancienne des « solde au » : le total ne vaut pas mieux que
    # son compte le moins frais.
    def as_of = anchored_accounts.filter_map(&:as_of).min

    # --- Ce qui doit rentrer -----------------------------------------------

    # Séjours à venir ou en cours avec un reste dû, à la date d'arrivée — ou
    # aujourd'hui pour un séjour déjà commencé.
    def upcoming_receivables
      @upcoming_receivables ||= receivables_where { |stay| stay.departure_date >= @today }
                                .each { |r| r.due_on = [r.stay.arrival_date || @today, @today].max }
                                .sort_by { |r| [r.due_on, r.stay.id] }
    end

    def late_receivables
      @late_receivables ||= receivables_where { |stay| stay.departure_date < @today && !stale?(stay) }
                            .sort_by { |r| [r.due_on, r.stay.id] }
    end

    def stale_receivables
      @stale_receivables ||= receivables_where { |stay| stale?(stay) }
                             .sort_by { |r| [r.due_on, r.stay.id] }
    end

    # --- Ce qui doit sortir ------------------------------------------------

    # Les dettes de la file « À payer », les charges fixes de l'horizon, puis
    # les mensualités des dettes et litiges qui y tombent.
    def outflows
      @outflows ||= (payable_outflows + recurring_outflows + liability_outflows.select { |o| o.due_on <= horizon_end })
                    .sort_by { |o| [o.due_on, outflow_rank(o)] }
    end

    # Toutes les mensualités restantes des dettes et litiges ouverts, horizon
    # ou pas : ce qui tombe au-delà des 90 jours n'est pas dans la courbe, mais
    # il est dû quand même — la page le chiffre à part.
    def liability_outflows
      @liability_outflows ||= liabilities.flat_map do |liability|
        liability.schedule(today: @today).map do |installment|
          Outflow.new(liability: liability, due_on: installment.due_on, amount_cents: installment.amount_cents)
        end
      end
    end

    def liabilities
      @liabilities ||= Liability.open.where(legal_entity_id: @entity.id)
                                .includes(:third_party).order(:expected_on, :id).to_a
    end

    def liabilities_retained_cents = liabilities.sum(&:remaining_cents)
    def liabilities_beyond_horizon_cents = liability_outflows_beyond_horizon.sum(&:amount_cents)

    def liability_outflows_beyond_horizon = liability_outflows.select { |o| o.due_on > horizon_end }

    # Ce qui pèse vraiment dans l'horizon : les sommes « à encaisser » et « à
    # payer » de « Peut-on dépenser ? » sont faites de ces listes-ci, et la
    # fenêtre de leur détail les relit telles quelles.
    def receivables_in_horizon = upcoming_receivables.select { |r| r.due_on <= horizon_end }
    def outflows_in_horizon = outflows.select { |o| o.due_on <= horizon_end }

    # Chaque occurrence d'une charge fixe entre aujourd'hui et la fin de
    # l'horizon — sauf celles qu'une vraie facture du même tiers couvre déjà :
    # la facture encodée dit le montant exact, l'estimation s'efface.
    def recurring_outflows
      @recurring_outflows ||= recurring_expenses.flat_map do |expense|
        expense.occurrences_between(@today, horizon_end)
               .reject { |due_on| covered_by_invoice?(expense, due_on) }
               .map { |due_on| Outflow.new(recurring_expense: expense, due_on: due_on, amount_cents: expense.amount_cents) }
      end
    end

    def payable_outflows
      @payable_outflows ||= payable_queue.rows.filter_map do |payable|
        next unless foundation_payable?(payable)

        amount = payable.remaining_cents
        next unless amount.positive?

        Outflow.new(payable: payable, amount_cents: amount,
                    due_on: [payable.payable_due_on || @today, @today].max)
      end
    end

    # --- La courbe ---------------------------------------------------------

    # Un point par semaine sur l'historique, et le point d'aujourd'hui.
    def history
      @history ||= begin
        dates = (history_start..@today).step(7).to_a
        dates << @today unless dates.last == @today
        dates.map { |date| Point.new(date: date, balance_cents: total_at(date), projected: false) }
      end
    end

    # Un point par jour où quelque chose bouge, plus aujourd'hui et la fin de
    # l'horizon : la courbe est une suite de marches, pas une pente.
    def projection
      @projection ||= begin
        by_day = projected_movements.group_by(&:date)
        today_moves = by_day.delete(@today).to_a
        running = balance_cents + today_moves.sum(&:amount_cents)
        points = [Point.new(date: @today, balance_cents: running, projected: true, movements: today_moves)]
        by_day.sort.each do |date, moves|
          running += moves.sum(&:amount_cents)
          points << Point.new(date: date, balance_cents: running, projected: true, movements: moves)
        end
        points << Point.new(date: horizon_end, balance_cents: running, projected: true) unless points.last.date == horizon_end
        points
      end
    end

    def incoming_cents = projected_movements.sum { |move| move.amount_cents.positive? ? move.amount_cents : 0 }
    def late_cents = late_receivables.sum(&:amount_cents)
    def upcoming_incoming_cents = incoming_cents - late_cents
    def outgoing_cents = projected_movements.sum { |move| move.amount_cents.negative? ? -move.amount_cents : 0 }

    # Le point bas part du solde AVANT les mouvements du jour : un séjour qui
    # arrive aujourd'hui ne doit pas afficher un « point bas » au-dessus du
    # solde disponible.
    def lowest_point
      start = Point.new(date: @today, balance_cents: balance_cents, projected: true)
      ([start] + projection).min_by { |point| [point.balance_cents, point.date] }
    end

    private

    def cash_accounts
      @cash_accounts ||= CashAccount.where(legal_entity_id: @entity.id, active: true).order(:id).to_a
    end

    # { cash_account_id => { date => centimes du jour } } — une requête pour
    # tous les comptes, les lignes exclues n'étant pas des mouvements.
    def movements
      @movements ||= begin
        by_account = Hash.new { |hash, key| hash[key] = {} }
        CashEntry.where(cash_account_id: cash_accounts.map(&:id))
                 .where.not(status: "excluded")
                 .group(:cash_account_id, :entry_date)
                 .sum(:amount_cents)
                 .each { |(account_id, date), cents| by_account[account_id][date] = cents.to_i }
        by_account
      end
    end

    # Somme cumulée des lignes d'un compte jusqu'à une date incluse.
    def lines_sum(account, date)
      movements[account.id].sum { |day, cents| day <= date ? cents : 0 }
    end

    # Le solde à une date = les lignes jusque-là, recalées sur l'ancre : ce que
    # la banque (ou le comptage) affirmait ce jour-là, moins ce que nos lignes
    # en disent. Sans ancre, pas de recalage — c'est un solde théorique.
    def balance_at(account, date)
      anchor = anchor_for(account)
      offset = anchor ? anchor.balance_cents - lines_sum(account, anchor.date) : 0
      offset + lines_sum(account, date)
    end

    def total_at(date) = anchored_accounts.sum { |row| balance_at(row.account, date) }

    def anchor_for(account)
      @anchors ||= {}
      return @anchors[account.id] if @anchors.key?(account.id)

      @anchors[account.id] =
        case account.kind
        when "bank"
          statement = CodaStatement.where(cash_account_id: account.id).where.not(new_balance_date: nil)
                                   .order(new_balance_date: :desc, id: :desc).first
          statement && Anchor.new(date: statement.new_balance_date, balance_cents: statement.new_balance_cents,
                                  source: "relevé CODA")
        when "cash"
          count = CashCount.validated.where(cash_account_id: account.id).ordered.first
          count && Anchor.new(date: count.counted_on, balance_cents: count.counted_cents, source: "comptage")
        end
    end

    # Les séjours qui engagent vraiment de l'argent : confirmés ou
    # pré-confirmés. Une demande en attente n'a rien promis, un séjour annulé ou
    # refusé non plus. Un séjour n'a pas d'entité : comme une dette sans
    # entité, il passe par la Fondation, qui l'encaisse sur son compte — la SRL
    # ne le compte pas une seconde fois.
    def candidate_stays
      return [] unless @entity.form == "foundation"

      @candidate_stays ||= Stay.where(status: Stay::BLOCKING_STATUSES)
                               .where.not(departure_date: nil)
                               .includes(:customer, { stay_items: :bookable },
                                         { experience_bookings: { experience_availability: :experience } })
                               .to_a
    end

    def amounts
      @amounts ||= Stays::IndexAmounts.new(candidate_stays).call
    end

    def receivables_where
      candidate_stays.filter_map do |stay|
        next unless yield(stay)

        due = amounts[stay.id].balance_due_cents
        next unless due.positive?

        Receivable.new(stay: stay, due_on: stay.arrival_date || stay.departure_date, amount_cents: due)
      end
    end

    def stale?(stay) = stay.departure_date < @today - STALE_AFTER_DAYS

    # À date égale : la vraie dette, puis la charge fixe, puis le litige.
    def outflow_rank(outflow)
      if outflow.liability? then 2
      elsif outflow.recurring? then 1
      else 0
      end
    end

    # Les mouvements attendus dans l'horizon, signés et nommés. Un séjour en
    # retard est attendu aujourd'hui, pas à son arrivée passée.
    def projected_movements
      @projected_movements ||=
        late_receivables.map { |r| Movement.new(date: @today, label: receivable_label(r), amount_cents: r.amount_cents) } +
        receivables_in_horizon.map { |r| Movement.new(date: r.due_on, label: receivable_label(r), amount_cents: r.amount_cents) } +
        outflows_in_horizon.map { |o| Movement.new(date: o.due_on, label: outflow_label(o), amount_cents: -o.amount_cents) }
    end

    def receivable_label(receivable)
      ["Séjour ##{receivable.stay.id}", receivable.stay.customer&.name].compact_blank.join(" — ")
    end

    # Le libellé de la file « À payer », avec son bénéficiaire quand il ne le
    # nomme pas déjà ; « charge fixe » ou le genre de la dette sinon, pour
    # qu'une estimation ne passe pas pour une facture.
    def outflow_label(outflow)
      if outflow.recurring?
        "#{outflow.recurring_expense.label} (charge fixe)"
      elsif outflow.liability?
        "#{outflow.liability.label} (#{outflow.liability.kind_label.downcase})"
      else
        payable = outflow.payable
        beneficiary = payable.payable_beneficiary.presence
        label = payable.payable_label
        beneficiary.nil? || label.include?(beneficiary) ? label : "#{label} — #{beneficiary}"
      end
    end

    def payable_queue = @payable_queue ||= Finance::PayableQueue.new

    def recurring_expenses
      RecurringExpense.actives.where(legal_entity_id: @entity.id).includes(:third_party).to_a
    end

    def covered_by_invoice?(expense, due_on)
      return false if expense.third_party_id.nil?

      period = expense.period_for(due_on)
      payable_outflows.any? do |outflow|
        outflow.payable.payable_third_party&.id == expense.third_party_id &&
          period.cover?(outflow.payable.payable_due_on || @today)
      end
    end

    # Une dette d'une autre entité (SRL, SSI) ne sort pas du compte de la
    # Fondation. Une dette sans entité (parts d'événements, relevés de
    # porteurs) est payée par la Fondation : elle ne pèse pas sur la SRL.
    def foundation_payable?(payable)
      entity_id = payable.try(:legal_entity_id)
      entity_id.nil? ? @entity.form == "foundation" : entity_id == @entity.id
    end
  end
end
