module Finance
  # L'arrêté du mois : ce qui reste à faire pour que la comptabilité du mois soit
  # finie, calculé depuis les données plutôt que coché à la main.
  #
  # La panne que ça répare n'est pas l'ignorance, c'est l'OUBLI. La note de
  # passation de Manon documente exactement ça : deux mois de bar impayés, la
  # cagnotte de février à juin jamais calculée, le décompte du dôme 2025 jamais
  # remis, les commissions Stripe 2026 non ventilées. Personne n'a décidé de ne
  # pas les faire — personne ne savait qu'ils restaient à faire.
  #
  # Une liste de cases à cocher aurait le même défaut : elle dit ce que quelqu'un
  # a déclaré, pas ce qui est vrai. Ici chaque étape interroge la base et rend
  # son propre état. Une écriture qui arrive en retard fait repasser l'étape au
  # rouge toute seule, et c'est précisément le comportement qu'on veut.
  #
  # Les huit étapes suivent l'ordre du travail réel, et chacune porte son lien
  # d'action : un écran qui dit « il manque quelque chose » sans dire où aller
  # fait perdre le temps qu'il prétend faire gagner.
  class MonthlyClose < ServiceBase
    Step = Struct.new(:key, :title, :status, :detail, :action_label, :action_path, keyword_init: true) do
      def done? = status == :done
      def blocking? = status == :todo
      def warning? = status == :warning
    end

    def initialize(month:)
      @month = month.beginning_of_month
      @from = @month
      @to = @month.end_of_month
    end

    def run
      catch_error { steps }
    end

    def run!
      steps
    end

    def self.call(month:) = new(month: month).run!

    private

    def steps
      [
        bank_lines_step,
        allocations_step,
        recurring_charges_step,
        statements_issued_step,
        statements_sent_step,
        settlements_step,
        controls_step,
        closing_step
      ]
    end

    # 1 — les mouvements bancaires du mois sont-ils entrés ? Un mois sans aucune
    # ligne n'est pas un mois calme : c'est un mois qu'on n'a pas importé.
    def bank_lines_step
      lignes = CashEntry.in_period(@from, @to).count

      if lignes.zero?
        Step.new(key: :bank_lines, title: "Les mouvements bancaires du mois sont entrés",
                 status: :todo, detail: "Aucune ligne de trésorerie sur le mois. Dépose le relevé CODA.",
                 action_label: "Importer un relevé", action_path: :coda)
      else
        Step.new(key: :bank_lines, title: "Les mouvements bancaires du mois sont entrés",
                 status: :done, detail: "#{lignes} ligne(s) de trésorerie sur le mois.",
                 action_label: "Voir le journal", action_path: :cash_entries)
      end
    end

    # 2 — le compteur qui doit tomber à zéro.
    def allocations_step
      restantes = CashEntry.pending.in_period(@from, @to)
      nombre = restantes.count

      if nombre.zero?
        Step.new(key: :allocations, title: "Tout est affecté", status: :done,
                 detail: "Aucune ligne en attente sur le mois.")
      else
        Step.new(key: :allocations, title: "Tout est affecté", status: :todo,
                 detail: "#{nombre} ligne(s) en attente, pour #{money(restantes.sum(:amount_cents))}.",
                 action_label: "Les affecter", action_path: :unallocated)
      end
    end

    # 3 — les charges récurrentes du mois. C'est l'étape qui a manqué pendant
    # cinq mois pour la cagnotte.
    def recurring_charges_step
      attendues = RecurringCharge.active_on(@month).to_a
      manquantes = attendues.reject { |charge| charge_generated?(charge) }

      if attendues.empty?
        Step.new(key: :recurring, title: "Les charges récurrentes sont générées", status: :warning,
                 detail: "Aucune charge récurrente active sur le mois — c'est peut-être normal, vérifie.",
                 action_label: "Voir les charges", action_path: :recurring)
      elsif manquantes.empty?
        Step.new(key: :recurring, title: "Les charges récurrentes sont générées", status: :done,
                 detail: "#{attendues.size} charge(s) récurrente(s) générée(s).")
      else
        Step.new(key: :recurring, title: "Les charges récurrentes sont générées", status: :todo,
                 detail: "#{manquantes.size} charge(s) pas encore générée(s) : " \
                         "#{manquantes.map(&:label).join(', ')}.",
                 action_label: "Les générer", action_path: :recurring)
      end
    end

    # 4 — un décompte par compte qui doit quelque chose.
    def statements_issued_step
      emis = AccountStatement.for_month(@month).pluck(:member_account_id)
      manquants = MemberAccount.actives.reject do |compte|
        emis.include?(compte.id) || compte.balance_cents.zero?
      end

      if manquants.empty?
        Step.new(key: :statements, title: "Les décomptes du mois sont émis", status: :done,
                 detail: "#{emis.size} décompte(s) émis.")
      else
        Step.new(key: :statements, title: "Les décomptes du mois sont émis", status: :todo,
                 detail: "#{manquants.size} compte(s) au solde non nul sans décompte : " \
                         "#{manquants.map(&:name).join(', ')}.",
                 action_label: "Les émettre", action_path: :statements)
      end
    end

    # 5 — émis ne veut pas dire envoyé. C'est exactement le trou par lequel deux
    # mois de bar sont restés impayés.
    def statements_sent_step
      decomptes = AccountStatement.for_month(@month).to_a
      # Rien à envoyer n'est pas un manquement. Bloquer là-dessus rendrait
      # impossible d'arrêter un mois sans décompte — et un écran qui refuse pour
      # une raison qu'on ne comprend pas est un écran qu'on cesse d'ouvrir.
      if decomptes.empty?
        return Step.new(key: :sent, title: "Les décomptes sont envoyés", status: :warning,
                        detail: "Aucun décompte à envoyer ce mois-ci.")
      end

      non_envoyes = decomptes.reject { |statement| statement.sent_at.present? || statement.status == "settled" }

      if non_envoyes.empty?
        Step.new(key: :sent, title: "Les décomptes sont envoyés", status: :done,
                 detail: "Tous les décomptes du mois sont partis.")
      else
        Step.new(key: :sent, title: "Les décomptes sont envoyés", status: :todo,
                 detail: "#{non_envoyes.size} décompte(s) émis mais jamais envoyés — " \
                         "émettre n'est pas envoyer.",
                 action_label: "Les envoyer", action_path: :statements)
      end
    end

    # 6 — les règlements. Non bloquant : un sourcier peut légitimement payer le
    # mois suivant. Mais il faut le VOIR.
    def settlements_step
      decomptes = AccountStatement.for_month(@month).to_a
      impayes = decomptes.reject { |statement| statement.status == "settled" }

      if decomptes.empty?
        Step.new(key: :settlements, title: "Les règlements sont enregistrés", status: :warning,
                 detail: "Rien à encaisser ce mois-ci.")
      elsif impayes.empty?
        Step.new(key: :settlements, title: "Les règlements sont enregistrés", status: :done,
                 detail: "Tous les décomptes du mois sont réglés.")
      else
        du = impayes.sum(&:closing_balance_cents)
        Step.new(key: :settlements, title: "Les règlements sont enregistrés", status: :warning,
                 detail: "#{impayes.size} décompte(s) encore ouverts, pour #{money(du)}. " \
                         "Ça n'empêche pas d'arrêter le mois — mais ça se relance.",
                 action_label: "Voir les décomptes", action_path: :statements)
      end
    end

    # 7 — les invariants. Les mêmes que les rakes, calculés ici pour que
    # personne n'ait à ouvrir un terminal pour savoir si la compta se tient.
    def controls_step
      ecarts = []
      ecarts << "des écritures déséquilibrées" if unbalanced_entries?
      ecarts << "des lignes de trésorerie sur-affectées" if over_allocated?
      ecarts << "des versements Stripe incomplets" if unbalanced_payouts?

      if ecarts.empty?
        Step.new(key: :controls, title: "Les contrôles comptables passent", status: :done,
                 detail: "Équilibre des écritures, affectations et versements : tout se referme.")
      else
        Step.new(key: :controls, title: "Les contrôles comptables passent", status: :todo,
                 detail: "À regarder : #{ecarts.join(', ')}.",
                 action_label: "Ouvrir la balance", action_path: :trial_balance)
      end
    end

    def closing_step
      closing = MonthClosing.find_by(period_month: @month)

      if closing
        Step.new(key: :closing, title: "Le mois est arrêté", status: :done,
                 detail: "Arrêté le #{I18n.l(closing.closed_at.to_date)}" \
                         "#{closing.closed_by.present? ? " par #{closing.closed_by}" : ''}.")
      else
        Step.new(key: :closing, title: "Le mois est arrêté", status: :todo,
                 detail: "Le mois n'est pas encore arrêté.")
      end
    end

    def charge_generated?(charge)
      AccountEntry.unscoped
                  .where("idempotency_key LIKE ?", "recurring:#{charge.id}:#{@month.strftime('%Y-%m')}%")
                  .exists?
    end

    # Les trois contrôles se font en AGRÉGAT, pas objet par objet. Une requête
    # par écriture de journal se remarque à peine sur un mois de rodage et
    # devient insupportable sur un mois chargé — or c'est précisément les mois
    # chargés qu'on a envie d'arrêter sans attendre.
    def unbalanced_entries?
      JournalLine.joins(:journal_entry)
                 .where(journal_entries: { entry_date: @from..@to })
                 .group("journal_entries.id")
                 .having("SUM(journal_lines.debit_cents) <> SUM(journal_lines.credit_cents)")
                 .pick(Arel.sql("journal_entries.id"))
                 .present?
    end

    def over_allocated?
      CashAllocation.joins(:cash_entry)
                    .where(cash_entries: { entry_date: @from..@to })
                    .group("cash_entries.id", "cash_entries.amount_cents")
                    .having("ABS(SUM(cash_allocations.amount_cents)) > ABS(cash_entries.amount_cents)")
                    .pick(Arel.sql("cash_entries.id"))
                    .present?
    end

    def unbalanced_payouts?
      StripeBalanceTransaction.joins(:stripe_payout)
                              .where(stripe_payouts: { arrival_date: @from..@to })
                              .where.not(kind: "payout")
                              .group("stripe_payouts.id", "stripe_payouts.amount_cents")
                              .having("SUM(stripe_balance_transactions.net_cents) <> stripe_payouts.amount_cents")
                              .pick(Arel.sql("stripe_payouts.id"))
                              .present?
    end

    def money(cents) = Money.new(cents, "EUR").format
  end
end
