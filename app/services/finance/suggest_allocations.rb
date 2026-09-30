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
  # 2. **Jev**, quand on le lui passe et seulement là où aucune règle ne
  #    s'applique (`JevSuggestion`). Il choisit parmi les comptes où la compta a
  #    envoyé des lignes semblables, et ne propose qu'au-dessus de son seuil.
  #    Une ligne n'est demandée qu'UNE fois (`jev_checked_at`) : sans réponse
  #    assez sûre, elle reste sans proposition plutôt que d'être redemandée à
  #    chaque ouverture d'écran.
  #
  # L'ancien « précédent du même IBAN » n'est plus une source (2026-09-30) :
  # mesuré sur 2025, il n'était juste qu'une fois sur deux, parce qu'un ménage
  # paie le bar, l'épicerie, le pain et ses charges depuis le même compte. Il
  # survit comme indice donné à Jev, qui le pèse avec le reste.
  class SuggestAllocations < ServiceBase
    def initialize(cash_entries: nil, whodunnit: nil, jev: nil)
      @entries = cash_entries || CashEntry.pending.includes(:cash_allocations)
      @whodunnit = whodunnit
      @jev = jev if jev&.configured?
    end

    def run
      catch_error { suggest }
    end

    def run!
      suggest
    end

    private

    def suggest
      rules = AllocationRule.actives.ordered.includes(:general_account, :team, :legal_entity, :event).to_a
      created = 0

      @entries.each do |entry|
        next if entry.posted? || entry.status == "excluded"
        next if entry.allocation_suggestions.pending.exists?
        next if entry.cash_allocations.any?

        suggestion = from_rules(entry, rules) || from_jev(entry)
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
          event: rule.event,
          amount_cents: entry.remaining_cents,
          confidence: rule.confidence,
          source: "rule",
          rationale: rule.event ? "#{motif} — événement « #{rule.event.name} »" : motif
        )
      end

      nil
    end

    # Une réponse de Jev, même trop peu sûre pour être proposée, clôt la
    # question pour cette ligne. Une panne, elle, ne la clôt pas : la ligne sera
    # redemandée à la prochaine ouverture.
    def from_jev(entry)
      return nil if @jev.nil? || entry.jev_checked_at.present?

      suggestion = JevSuggestion.new(cash_entry: entry, jev: @jev).call
      entry.update_column(:jev_checked_at, Time.current)
      suggestion
    rescue Jev::Client::Error => e
      Rails.logger.warn("[SuggestAllocations] Jev indisponible pour la ligne ##{entry.id} : #{e.message}")
      nil
    end
  end
end
