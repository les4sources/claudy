module Mcp
  module Tools
    module Finances
      # Les boutons d'une ligne de trésorerie : accepter ou refuser la
      # suggestion (AllocationSuggestionsController), comptabiliser, annuler la
      # passation, exclure, retirer une affectation (CashEntriesController,
      # CashAllocationsController#destroy).
      class GesteLigneTresorerie < Ecriture
        include Commun

        GESTES = {
          "accepter_suggestion" => "accepter la suggestion d'affectation (comptabilise si la ligne est couverte)",
          "refuser_suggestion" => "refuser la suggestion (elle ne se représentera plus)",
          "comptabiliser" => "passer l'écriture d'une ligne entièrement affectée",
          "annuler_passation" => "contre-passer l'écriture : la ligne redevient réaffectable (motif obligatoire)",
          "exclure" => "sortir la ligne du circuit (doublon, erreur d'import) ; le motif est obligatoire et reste visible",
          "retirer_affectation" => "retirer une affectation (ligne non comptabilisée)"
        }.freeze

        tool "geste_ligne_tresorerie",
             title: "Geste sur une ligne de trésorerie",
             description: "Un geste sur une ligne : #{GESTES.map { |cle, sens| "#{cle} (#{sens})" }.join(' ; ')}.",
             schema: {
               properties: {
                 ligne: LIGNE,
                 geste: { type: "string", enum: GESTES.keys },
                 affectation: { type: %w[integer string], description: "Pour retirer_affectation : l'affectation (#id), rendue par fiche_ligne_tresorerie." }
               },
               required: %w[ligne geste]
             }

        private

        def planifier(arguments)
          entry = ligne!(arguments["ligne"])
          geste = arguments["geste"].to_s
          raise Error, "geste : #{GESTES.keys.join(', ')}." unless GESTES.key?(geste)

          resume, donnees = send("plan_#{geste}", entry, arguments)
          Plan.new(resume: "#{ligne_tresorerie(entry)}\n#{resume}",
                   empreinte: [etat_de(entry), entry.cash_allocations.map(&:id).sort, signature(arguments)],
                   donnees: donnees.merge(geste: geste, id: entry.id))
        end

        def appliquer(plan)
          d = plan.donnees
          entry = CashEntry.find(d[:id])
          metier! do
            case d[:geste]
            when "accepter_suggestion"
              ::Finance::AcceptSuggestion.new(suggestion: AllocationSuggestion.find(d[:suggestion]), whodunnit: whodunnit).run!
              "Suggestion acceptée. #{ligne_tresorerie(entry.reload)}"
            when "refuser_suggestion"
              suggestion = AllocationSuggestion.find(d[:suggestion])
              suggestion.update!(status: "rejected", decided_at: Time.current, decided_by: whodunnit)
              suggestion.allocation_rule&.increment!(:rejected_count)
              "Suggestion refusée."
            when "comptabiliser"
              ::Accounting::PostCashEntry.new(cash_entry: entry, whodunnit: whodunnit).run!
              "Ligne comptabilisée : l'écriture est au grand livre."
            when "annuler_passation"
              ::Accounting::UnpostCashEntry.new(cash_entry: entry, whodunnit: whodunnit).run!
              "Passation annulée : l'écriture est contre-passée, la ligne est réaffectable."
            when "exclure"
              if entry.cash_account.kind == "cash"
                ::Finance::UpdateCashLine.new(cash_entry: entry, whodunnit: whodunnit).exclude!(@motif)
              else
                entry.exclude!(@motif)
              end
              "Ligne exclue : #{@motif}"
            when "retirer_affectation"
              affectation = entry.cash_allocations.find(d[:affectation])
              raise Error, affectation.errors.full_messages.to_sentence unless affectation.destroy

              ::Shop::ConsignorTransfer.new(cash_entry: entry.reload).unlink_if_orphan!
              "Affectation retirée. #{ligne_tresorerie(entry.reload)}"
            end
          end
        end

        def suggestion!(entry)
          entry.allocation_suggestions.pending.ordered.first ||
            raise(Error, "Cette ligne n'a pas de suggestion en attente (fiche_ligne_tresorerie la calcule).")
        end

        def plan_accepter_suggestion(entry, _arguments)
          s = suggestion!(entry)
          raise Error, "Cette ligne est déjà comptabilisée." if entry.posted?

          apres = simuler do
            metier! { ::Finance::AcceptSuggestion.new(suggestion: AllocationSuggestion.find(s.id), whodunnit: whodunnit).run! }
            ligne_tresorerie(CashEntry.find(entry.id))
          end
          ["Accepter la suggestion ##{s.id} (#{s.source_label}, #{s.confidence} %) : → #{s.general_account}" \
           "#{" · pôle #{s.team.name}" if s.team} · #{s.legal_entity&.name}\n  Pourquoi : #{s.rationale}\nAprès : #{apres}",
           { suggestion: s.id }]
        end

        def plan_refuser_suggestion(entry, _arguments)
          s = suggestion!(entry)
          ["Refuser la suggestion ##{s.id} → #{s.general_account}. Elle ne se représentera plus pour cette ligne.", { suggestion: s.id }]
        end

        def plan_comptabiliser(entry, _arguments)
          raise Error, "Cette ligne est déjà comptabilisée." if entry.posted?
          raise Error, "Il reste #{euros(entry.remaining_cents)} à affecter avant de comptabiliser." unless entry.fully_allocated?

          ["Passer l'écriture au journal #{entry.journal == 'cash' ? 'de caisse' : 'de banque'} :\n" +
           entry.cash_allocations.map { |a| "  #{ligne_affectation(a)}" }.join("\n"), {}]
        end

        def plan_annuler_passation(entry, _arguments)
          motif!({ "motif" => @motif })
          raise Error, "Cette ligne n'est pas comptabilisée." unless entry.posted?

          ["Contre-passer son écriture (datée d'aujourd'hui). Les affectations restent, la ligne repasse « à affecter » " \
           "et redevient modifiable.", {}]
        end

        def plan_exclure(entry, _arguments)
          motif!({ "motif" => @motif })
          raise Error, "Cette ligne est déjà exclue." if entry.status == "excluded"
          if entry.posted? && entry.cash_account.kind != "cash"
            raise Error, "Cette ligne est comptabilisée : annule d'abord sa passation (annuler_passation)."
          end

          ["EXCLURE la ligne, motif « #{@motif} »#{' (son écriture de caisse sera contre-passée)' if entry.posted?}. " \
           "Elle quitte la file et la trésorerie, mais reste visible avec son motif.", {}]
        end

        def plan_retirer_affectation(entry, arguments)
          raise Error, "Donne l'affectation à retirer." if arguments["affectation"].blank?
          raise Error, "Cette ligne est comptabilisée : annule d'abord sa passation." if entry.posted?

          affectation = entry.cash_allocations.find { |a| a.id == id!(arguments["affectation"], "affectation") } ||
                        raise(Error, "Cette ligne n'a pas d'affectation ##{arguments['affectation']}.")
          paiement = affectation.document.is_a?(PurchaseInvoice) || affectation.document.is_a?(ExpenseReport)
          ["Retirer #{ligne_affectation(affectation)}#{' — le document repassera « à payer »' if paiement}.", { affectation: affectation.id }]
        end
      end
    end
  end
end
