module Finance
  # Produit des suggestions d'affectation pour les lignes en attente (issue #183).
  #
  # **Ce service ne crée AUCUNE allocation.** Il propose, motive, et s'arrête là.
  # C'est l'invariant central du rapprochement assisté : une machine qui affecte
  # toute seule finit toujours par affecter mal, et personne ne le voit avant
  # l'arrêté annuel. Une machine qui propose fait gagner le même temps sans
  # jamais mentir.
  #
  # Deux sources, dans cet ordre :
  #
  # 1. **Les règles**, parcourues dans l'ordre choisi par la compta. La première
  #    qui matche gagne — c'est ce qui rend l'ordre signifiant et permet de
  #    poser une règle très spécifique avant une règle générale.
  # 2. **Le précédent du même IBAN** : si un humain a déjà affecté une ligne
  #    venant de ce compte, on le propose. C'est ce qui fait qu'au deuxième
  #    virement d'un fournisseur récurrent, la ventilation se propose seule sans
  #    qu'on ait écrit la moindre règle. La confiance est bornée plus bas qu'une
  #    règle explicite : un précédent n'est pas une intention.
  class SuggestAllocations < ServiceBase
    IBAN_HISTORY_CONFIDENCE = 60

    def initialize(cash_entries: nil, whodunnit: nil)
      @entries = cash_entries || CashEntry.pending.includes(:cash_allocations)
      @whodunnit = whodunnit
    end

    def run
      catch_error { suggest }
    end

    def run!
      suggest
    end

    private

    def suggest
      rules = AllocationRule.actives.ordered.includes(:general_account, :team, :legal_entity).to_a
      created = 0

      @entries.each do |entry|
        next if entry.posted? || entry.status == "excluded"
        next if entry.allocation_suggestions.pending.exists?
        next if entry.cash_allocations.any?

        suggestion = from_rules(entry, rules) || from_iban_history(entry)
        next if suggestion.nil?

        # Une proposition déjà refusée ne se represente pas : la reproposer à
        # chaque ouverture d'écran transformerait le refus en formalité, et on
        # finirait par accepter d'épuisement.
        next if already_rejected?(entry, suggestion)

        begin
          suggestion.save!
          created += 1
        rescue ActiveRecord::RecordNotUnique
          # Une autre ouverture d'écran a gagné la course : l'index partiel a
          # tranché, il n'y a rien à faire de plus.
          next
        end
      end

      created
    end

    def already_rejected?(entry, suggestion)
      scope = entry.allocation_suggestions.where(status: "rejected")
      scope = if suggestion.allocation_rule_id.present?
                scope.where(allocation_rule_id: suggestion.allocation_rule_id)
              else
                scope.where(source: suggestion.source, general_account_id: suggestion.general_account_id)
              end
      scope.exists?
    end

    def from_rules(entry, rules)
      rules.each do |rule|
        motif = rule.match(entry)
        next if motif.nil?

        return entry.allocation_suggestions.new(
          allocation_rule: rule,
          general_account: rule.general_account,
          analytic_account: rule.analytic_account,
          team: rule.team,
          legal_entity: rule.legal_entity,
          amount_cents: entry.remaining_cents,
          confidence: rule.confidence,
          source: "rule",
          rationale: motif
        )
      end

      nil
    end

    # Le précédent : la dernière affectation humaine sur une ligne du même IBAN.
    # On ne remonte que les lignes déjà comptabilisées — une affectation en
    # cours n'est pas encore une décision.
    def from_iban_history(entry)
      return nil if entry.counterparty_iban.blank?

      precedente = CashEntry.where(counterparty_iban: entry.counterparty_iban)
                            .where.not(id: entry.id)
                            .where(status: "allocated")
                            .order(entry_date: :desc)
                            .first
      return nil if precedente.nil?

      allocation = precedente.cash_allocations.order(:id).first
      return nil if allocation.nil?

      entry.allocation_suggestions.new(
        general_account: allocation.general_account,
        analytic_account: allocation.analytic_account,
        team: allocation.team,
        legal_entity: allocation.legal_entity,
        amount_cents: entry.remaining_cents,
        confidence: IBAN_HISTORY_CONFIDENCE,
        source: "iban_history",
        rationale: "Le #{I18n.l(precedente.entry_date)}, une ligne du même IBAN a été affectée à " \
                   "#{allocation.general_account} par la compta."
      )
    end
  end
end
