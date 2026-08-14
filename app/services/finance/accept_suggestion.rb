module Finance
  # Transforme une suggestion en affectation — le SEUL chemin par lequel une
  # proposition devient une décision (issue #183).
  #
  # Le geste humain est ici, et nulle part ailleurs. Que ce soit un clic unitaire
  # ou une acceptation en masse bornée, il passe par ce service : c'est ce qui
  # garantit qu'aucune ligne ne s'affecte sans que quelqu'un l'ait voulu.
  class AcceptSuggestion < ServiceBase
    class AlreadyDecided < StandardError; end
    class EntryPosted < StandardError; end

    def initialize(suggestion:, whodunnit: nil)
      @suggestion = suggestion
      @whodunnit = whodunnit
    end

    def run
      catch_error(context: { suggestion: @suggestion.id }) { accept }
    end

    def run!
      accept
    end

    private

    def accept
      entry = @suggestion.cash_entry
      allocation = nil

      ApplicationRecord.transaction do
        # Verrou et re-tests DANS la transaction : sans eux, deux acceptations
        # simultanées de la même suggestion passeraient toutes les deux le test
        # d'état et la seconde échouerait en 500 au lieu de dire « déjà traitée ».
        @suggestion.lock!
        entry.lock!

        raise AlreadyDecided, "Cette suggestion a déjà été traitée." unless @suggestion.status == "pending"
        raise EntryPosted, "Cette ligne est déjà comptabilisée." if entry.reload.posted?

        montant = [@suggestion.amount_cents.abs, entry.remaining_cents.abs].min
        montant = entry.incoming? ? montant : -montant

        allocation = entry.cash_allocations.create!(
          general_account: @suggestion.general_account,
          analytic_account: @suggestion.analytic_account,
          team: @suggestion.team,
          legal_entity: @suggestion.legal_entity,
          amount_cents: montant,
          label: "Suggestion acceptée"
        )

        @suggestion.update!(status: "accepted", decided_at: Time.current, decided_by: @whodunnit)
        @suggestion.allocation_rule&.increment!(:accepted_count)
      end

      # La comptabilisation suit si la ligne est entièrement affectée : demander
      # un second clic pour un geste qui n'a plus de décision à prendre, c'est
      # la meilleure façon de laisser des lignes affectées mais non passées.
      if entry.reload.fully_allocated?
        Accounting::PostCashEntry.new(cash_entry: entry, whodunnit: @whodunnit).run!
      end

      allocation
    end
  end
end
