module Finance
  # Accepter ou refuser une proposition (issue #183).
  #
  # Il n'existe volontairement AUCUN bouton « tout accepter ». L'acceptation en
  # masse existe, mais elle est bornée par une règle ET un seuil de confiance, et
  # l'écran annonce combien de lignes seront touchées avant qu'on valide. « Tout
  # accepter » est le geste par lequel une machine finit par décider à notre
  # place sans qu'on s'en aperçoive.
  class AllocationSuggestionsController < Finance::AccountingBaseController
    include Finance::UnallocatedQueue

    def update
      suggestion = AllocationSuggestion.find(params[:id])

      case params[:decision]
      when "accept"
        Finance::AcceptSuggestion.new(suggestion: suggestion, whodunnit: current_user&.email,
                                      consignor: chosen_consignor).run!
        apres_decision(suggestion, notice: "Suggestion acceptée — la ligne est affectée.")
      when "reject"
        # Seule une suggestion encore proposée se refuse : refuser une
        # suggestion déjà acceptée fausserait les compteurs sans rien défaire
        # de l'affectation qu'elle a produite.
        unless suggestion.status == "pending"
          return apres_decision(suggestion, alert: "Cette suggestion a déjà été traitée.")
        end

        suggestion.update!(status: "rejected", decided_at: Time.current, decided_by: current_user&.email)
        suggestion.allocation_rule&.increment!(:rejected_count)
        apres_decision(suggestion, notice: "Suggestion refusée.")
      else
        apres_decision(suggestion, alert: "Décision inconnue.")
      end
    rescue Finance::AcceptSuggestion::AlreadyDecided, Finance::AcceptSuggestion::EntryPosted => e
      apres_decision(suggestion, alert: e.message)
    end

    # Acceptation en masse, bornée par règle et par seuil.
    def bulk
      rule = AllocationRule.find_by(id: params[:allocation_rule_id])

      if rule.nil?
        return redirect_to finance_allocation_rules_path,
                           alert: "Choisis une règle : il n'existe pas d'acceptation « toutes règles confondues »."
      end

      lot = Finance::BulkAcceptSuggestions.new(rule: rule, threshold: params[:confidence], whodunnit: current_user&.email)
      resultat = lot.run!

      redirect_to finance_allocation_rules_path,
                  notice: "#{resultat.accepted} suggestion(s) acceptée(s) pour la règle « #{rule.label} » " \
                          "au-dessus de #{lot.threshold} % de confiance."
    end

    private

    # L'artisan choisi sur la carte d'une suggestion au compte artisanat (epic
    # #359, phase 4). Le champ absent (autres suggestions), on laisse le
    # mot-clé décider ; présent mais vide, l'humain a dit « personne ».
    def chosen_consignor
      return :match unless params.key?(:consignor_id)

      Consignor.find_by(id: params[:consignor_id].presence)
    end

    # Depuis la file, la ligne répond en place ; d'ailleurs (fiche d'une
    # ligne), retour à la page d'où l'on vient, comme avant.
    def apres_decision(suggestion, notice: nil, alert: nil)
      if depuis_la_file?
        repondre_dans_la_file(suggestion.cash_entry, notice: notice, alert: alert)
      else
        redirect_back fallback_location: finance_unallocated_cash_entries_path, notice: notice, alert: alert
      end
    end
  end
end
