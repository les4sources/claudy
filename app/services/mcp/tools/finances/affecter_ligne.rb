module Mcp
  module Tools
    module Finances
      # Affecter une ligne de trésorerie à un ou plusieurs comptes du plan
      # (CashAllocationsController#create) : une part ou plusieurs, ensemble ou
      # pas du tout. Une ligne entièrement affectée se comptabilise dans la
      # foulée, comme à l'écran.
      class AffecterLigne < Ecriture
        include Commun

        PART = {
          type: "object",
          additionalProperties: false,
          properties: {
            compte: COMPTE_GENERAL,
            montant: MONTANT.merge(description: "Montant de la part en euros, sans signe (le sens est celui de la ligne). " \
                                                "Facultatif pour une part unique : le reste de la ligne."),
            pole: POLE,
            entite: ENTITE.merge(description: "Entité qui porte la part. Défaut : celle du compte de trésorerie."),
            analytique: { type: "string", description: "Compte analytique (code ou nom), facultatif." },
            libelle: { type: "string" },
            evenement: { type: %w[integer string], description: "Événement (#id) dont c'est une recette, facultatif." }
          },
          required: %w[compte]
        }.freeze

        tool "affecter_ligne",
             title: "Affecter une ligne de trésorerie",
             description: "Affecte une ligne de la file « À affecter » à des comptes du plan comptable, en une ou " \
                          "plusieurs parts (une nuitée et des consommations, une salle et un repas). Les parts " \
                          "s'enregistrent toutes ou aucune ; leur somme ne dépasse pas ce qui reste à affecter. Une " \
                          "ligne entièrement affectée est comptabilisée dans la foulée. Pour un séjour, une facture, " \
                          "une note de frais ou le compte d'un habitant, préférer rapprocher_ligne.",
             schema: {
               properties: {
                 ligne: LIGNE,
                 parts: { type: "array", items: PART, minItems: 1 }
               },
               required: %w[ligne parts]
             }

        private

        def planifier(arguments)
          entry = ligne!(arguments["ligne"])
          raise Error, "Cette ligne est exclue : elle n'attend plus d'affectation." if entry.status == "excluded"
          raise Error, "Cette ligne est comptabilisée : annule sa passation avant de la réaffecter (geste_ligne_tresorerie)." if entry.posted?

          reste = entry.remaining_cents
          raise Error, "Cette ligne est déjà entièrement affectée." if reste.zero?

          parts = Array(arguments["parts"])
          raise Error, "Donne au moins une part." if parts.empty?

          signe = entry.incoming? ? 1 : -1
          attributs = parts.each_with_index.map { |part, index| part!(part, index, parts.size, entry, reste, signe) }
          total = attributs.sum { |a| a[:amount_cents] }
          if total.abs > reste.abs
            raise Error, "Les parts font #{euros(total.abs)}, il ne reste que #{euros(reste.abs)} à affecter sur cette ligne."
          end

          apres = simuler { ecrire(entry.id, attributs) }
          resume = [ligne_tresorerie(entry), "Affecter :"]
          resume += attributs.map { |a| "  #{decrire(a)}" }
          resume << "Après : #{apres}"
          Plan.new(resume: resume.join("\n"),
                   empreinte: [etat_de(entry), entry.cash_allocations.map(&:id).sort, signature(arguments)],
                   donnees: { id: entry.id, attributs: attributs })
        end

        def appliquer(plan)
          ecrire(plan.donnees[:id], plan.donnees[:attributs])
        end

        def ecrire(id, attributs)
          entry = CashEntry.find(id)
          creees = metier! do
            entry.with_lock do
              attributs.map { |a| CashAllocation.create!(a.except(:evenement_id).merge(cash_entry: entry, document: a[:evenement_id] && Event.find(a[:evenement_id]))) }
            end
          end
          artisan = lier_artisan(entry, creees)
          entry.reload
          return "#{creees.size} part(s) enregistrée(s), il reste #{euros(entry.remaining_cents)} à affecter.#{artisan}" unless entry.fully_allocated?

          "ligne entièrement affectée#{comptabiliser(entry)}.#{artisan}"
        end

        # Comme l'écran : un exercice manquant n'annule pas l'affectation, il
        # laisse la ligne affectée mais non passée, et le dit.
        def comptabiliser(entry)
          metier! do
            ::Accounting::PostCashEntry.new(cash_entry: entry, whodunnit: whodunnit).run!
            " et comptabilisée"
          rescue ::Accounting::PostDocument::MissingFiscalYear => e
            ", mais pas comptabilisée : #{e.message}"
          end
        end

        # Le compte artisanat dit À QUI revient le virement : l'artisan que
        # nomme la communication (« ARTISANAT EMILIE »), comme l'acceptation
        # d'une suggestion. Personne de reconnu : la ligne reste sans artisan.
        def lier_artisan(entry, allocations)
          transfert = ::Shop::ConsignorTransfer.new(cash_entry: entry)
          return "" unless allocations.any? { |a| transfert.craft_allocation?(a.general_account_id) }

          artisan = transfert.suggested_consignor
          transfert.link!(artisan)
          artisan ? " Virement rattaché à l'artisan #{artisan.name}." : " Aucun artisan reconnu dans la communication : à préciser dans Claudy."
        end

        def part!(part, index, nombre, entry, reste, signe)
          part = part.to_h
          quoi = nombre > 1 ? "part #{index + 1} : " : ""
          compte = compte_general!(part["compte"])
          montant = if part["montant"].present?
                      cents!(part["montant"], "#{quoi}montant").abs
                    elsif nombre == 1
                      reste.abs
                    else
                      raise Error, "#{quoi}donne le montant (plusieurs parts)."
                    end
          {
            general_account_id: compte.id,
            amount_cents: signe * montant,
            team_id: part["pole"].present? ? pole!(part["pole"]).id : nil,
            legal_entity_id: (part["entite"].present? ? entite!(part["entite"]) : entry.cash_account.legal_entity).id,
            analytic_account_id: part["analytique"].present? ? analytique!(part["analytique"]).id : nil,
            label: part["libelle"].to_s.strip.presence,
            evenement_id: part["evenement"].present? ? evenement!(part["evenement"]).id : nil
          }
        end

        def evenement!(reference)
          Event.find_by(id: id!(reference, "événement")) || raise(Error, "Aucun événement ##{reference.to_s.delete('#')}.")
        end

        def decrire(attributs)
          compte = GeneralAccount.find(attributs[:general_account_id])
          details = ["#{euros(attributs[:amount_cents])} → #{compte}"]
          details << "pôle #{Team.find(attributs[:team_id]).name}" if attributs[:team_id]
          details << LegalEntity.find(attributs[:legal_entity_id]).name
          details << "analytique #{AnalyticAccount.find(attributs[:analytic_account_id])}" if attributs[:analytic_account_id]
          details << "événement #{Event.find(attributs[:evenement_id]).name}" if attributs[:evenement_id]
          details << "« #{attributs[:label]} »" if attributs[:label]
          details << "SANS PÔLE (restera « non ventilée »)" unless attributs[:team_id] || compte.klass.to_i < 6
          details.join(" · ")
        end
      end
    end
  end
end
