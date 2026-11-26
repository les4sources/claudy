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
    # Combien de lignes interrogent Jev en même temps (cf. `from_jev`).
    JEV_EN_PARALLELE = 8

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
      rules = AllocationRule.actives.ordered.includes(:general_account, :team, :legal_entity, :event, :cash_account).to_a
      created = 0
      pour_jev = []

      @entries.each do |entry|
        next if entry.posted? || entry.status == "excluded"
        next if entry.allocation_suggestions.pending.exists?
        next if entry.cash_allocations.any?

        suggestion = from_rules(entry, rules)
        if suggestion
          created += 1 if record(entry, suggestion)
        elsif @jev && entry.jev_checked_at.nil?
          pour_jev << entry
        end
      end

      from_jev(pour_jev).each { |entry, suggestion| created += 1 if record(entry, suggestion) }
      created
    end

    def record(entry, suggestion)
      # Une proposition déjà refusée ne se represente pas : la reproposer à
      # chaque ouverture d'écran transformerait le refus en formalité, et on
      # finirait par accepter d'épuisement.
      return false if already_rejected?(entry, suggestion)

      suggestion.save!
      true
    rescue ActiveRecord::RecordNotUnique
      # Une autre ouverture d'écran a gagné la course : l'index partiel a
      # tranché, il n'y a rien à faire de plus.
      false
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
    #
    # Les questions se préparent une à une (elles lisent la base), puis partent
    # à Jev EN MÊME TEMPS, par paquets de `JEV_EN_PARALLELE` : « Proposer pour
    # toutes les lignes affichées » en pose cinquante d'un coup, et cinquante
    # fois 300 ms à la file, c'est un quart de minute devant un écran figé.
    # Les fils ne font que l'appel HTTP : aucun ne touche la base.
    def from_jev(entries)
      return [] if entries.empty?

      questions = entries.map do |entry|
        jev = JevSuggestion.new(cash_entry: entry, jev: @jev)
        [entry, jev, jev.prepare]
      end

      reponses = ask_jev(questions.filter_map { |entry, _, prepared| [entry.id, prepared] if prepared })

      questions.filter_map do |entry, jev, prepared|
        reponse = prepared && reponses[entry.id]
        if reponse.is_a?(Jev::Client::Error)
          Rails.logger.warn("[SuggestAllocations] Jev indisponible pour la ligne ##{entry.id} : #{reponse.message}")
          next
        end

        entry.update_column(:jev_checked_at, Time.current)
        suggestion = prepared && jev.build(prepared, reponse)
        [entry, suggestion] if suggestion
      end
    end

    # { cash_entry_id => réponses de Jev, ou l'erreur qui l'a empêché }.
    def ask_jev(prepared_by_id)
      prepared_by_id.each_slice(JEV_EN_PARALLELE).each_with_object({}) do |paquet, reponses|
        fils = paquet.map do |id, prepared|
          Thread.new do
            [id, @jev.ask(state: prepared.state, questions: prepared.questions)]
          rescue Jev::Client::Error => e
            [id, e]
          end
        end
        # Le fil principal tient le verrou de chargement de Rails pendant la
        # requête : on le prête le temps d'attendre, au cas où un fil aurait
        # une constante à charger.
        ActiveSupport::Dependencies.interlock.permit_concurrent_loads do
          fils.each { |fil| reponses.store(*fil.value) }
        end
      end
    end
  end
end
