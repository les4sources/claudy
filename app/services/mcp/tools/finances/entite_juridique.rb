module Mcp
  module Tools
    module Finances
      # Paramètres > Entités juridiques (LegalEntitiesController #create, #update et
      # #destroy). Une entité qui porte des exercices, des comptes de
      # trésorerie ou des écritures ne se supprime pas : elle se désactive.
      class EntiteJuridique < Ecriture
        include Commun

        FORMES = { "fondation" => "foundation", "societe_simple" => "simple_company", "srl" => "srl" }.freeze
        TVA = { "exemptee" => "exempt", "assujettie" => "subject", "franchise" => "franchise" }.freeze

        tool "entite_juridique",
             title: "Créer, corriger ou supprimer une entité juridique",
             description: "Une entité qui tient sa comptabilité (la fondation, la société simple…) : nom, forme, régime " \
                          "de TVA, numéro de TVA, active. `supprimer` la retire si elle ne porte ni exercice, ni compte " \
                          "de trésorerie, ni écriture ; sinon, désactive-la. Les entités : parametrage_compta entites.",
             schema: {
               properties: {
                 entite: ENTITE.merge(description: "Pour corriger ou supprimer : l'entité (nom ou #id). Absente : nouvelle entité."),
                 supprimer: { type: "boolean" },
                 nom: { type: "string" },
                 forme: { type: "string", enum: FORMES.keys, description: "Défaut à la création : fondation." },
                 tva: { type: "string", enum: TVA.keys, description: "Régime de TVA. Défaut à la création : exemptee." },
                 numero_tva: { type: "string", description: "Chaîne vide pour l'effacer." },
                 active: { type: "boolean" }
               }
             }

        private

        def planifier(arguments)
          entite = arguments["entite"].present? ? entite_meme_inactive!(arguments["entite"]) : nil
          if arguments["supprimer"]
            raise Error, "Donne l'entité à supprimer." if entite.nil?
            unless entite.deletable?
              raise Error, "#{entite.name} porte #{entite.deletion_blockers.map { |quoi, n| "#{n} #{BLOCAGES[quoi]}" }.join(', ')} : " \
                           "désactive-la (active: false) plutôt que de la supprimer."
            end

            return Plan.new(resume: "Supprimer l'entité #{ligne_entite(entite)}.", empreinte: [etat_de(entite), "supprimer"],
                            donnees: { id: entite.id, supprimer: true })
          end

          attributs = attributs!(arguments, entite)
          raise Error, "Rien à changer." if entite && attributs.empty?

          apres = simuler { ecrire(entite&.id, attributs) }
          resume = entite ? "Corriger : #{ligne_entite(entite)}\nAprès : #{apres}" : "Nouvelle entité : #{apres}"
          Plan.new(resume: resume, empreinte: [entite && etat_de(entite), attributs.transform_values(&:to_s).sort],
                   donnees: { id: entite&.id, attributs: attributs })
        end

        BLOCAGES = { fiscal_years: "exercice(s)", cash_accounts: "compte(s) de trésorerie", journal_entries: "écriture(s)" }.freeze

        def appliquer(plan)
          if plan.donnees[:supprimer]
            entite = LegalEntity.find(plan.donnees[:id])
            raise Error, "Cette entité porte des exercices ou des écritures : désactive-la plutôt." unless entite.destroy

            return "Entité « #{entite.name} » supprimée."
          end

          "Entité enregistrée : #{ecrire(plan.donnees[:id], plan.donnees[:attributs])}"
        end

        def ecrire(id, attributs)
          entite = id ? LegalEntity.find(id) : LegalEntity.new
          metier! { entite.update!(attributs) }
          ligne_entite(entite.reload)
        end

        def ligne_entite(e)
          "##{e.id} #{e.name} · #{e.form_label} · TVA #{e.vat_regime_label.downcase}#{" n° #{e.vat_number}" if e.vat_number.present?}" \
            "#{' · INACTIVE' unless e.active?}"
        end

        def attributs!(arguments, entite)
          a = {}
          a[:name] = arguments["nom"].to_s.strip if arguments["nom"].present?
          a[:form] = FORMES[arguments["forme"]] || raise(Error, "forme : #{FORMES.keys.join(', ')}.") if arguments["forme"].present?
          a[:vat_regime] = TVA[arguments["tva"]] || raise(Error, "tva : #{TVA.keys.join(', ')}.") if arguments["tva"].present?
          a[:vat_number] = arguments["numero_tva"].to_s.strip.presence if arguments.key?("numero_tva")
          a[:active] = arguments["active"] unless arguments["active"].nil?
          return a if entite
          raise Error, "Pour créer une entité, donne son nom." if a[:name].blank?

          { form: "foundation", vat_regime: "exempt" }.merge(a)
        end
      end
    end
  end
end
