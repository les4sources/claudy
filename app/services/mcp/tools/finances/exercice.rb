module Mcp
  module Tools
    module Finances
      # Comptabilité > Exercices (FiscalYearsController #create, #update,
      # #close et #destroy). Clôturer est le geste qui fige : les écritures de
      # l'exercice ne se corrigent plus que par contre-passation.
      class Exercice < Ecriture
        include Commun

        tool "exercice",
             title: "Créer, corriger, clôturer ou supprimer un exercice comptable",
             description: "L'exercice d'une entité : dates de début et de fin (sans chevaucher un autre exercice de la " \
                          "même entité). `cloturer` le fige : plus aucune écriture ne s'y passe ni ne s'y corrige, sauf " \
                          "par contre-passation ; dis-le avant qu'il accepte. `supprimer` retire un exercice ouvert et " \
                          "vide. Les exercices : parametrage_compta exercices.",
             schema: {
               properties: {
                 exercice: { type: %w[integer string], description: "Pour corriger, clôturer ou supprimer : l'exercice (#id, ou l'année avec `entite`). Absent : nouvel exercice." },
                 entite: ENTITE.merge(description: "L'entité de l'exercice (à la création, ou pour le désigner par son année)."),
                 debut: DATE.merge(description: "Défaut à la création : le 1er janvier de l'année en cours."),
                 fin: DATE.merge(description: "Défaut à la création : le 31 décembre de l'année de début."),
                 cloturer: { type: "boolean" },
                 supprimer: { type: "boolean" }
               }
             }

        private

        def planifier(arguments)
          exercice = arguments["exercice"].present? ? exercice!(arguments) : nil
          if arguments["cloturer"] || arguments["supprimer"]
            raise Error, "Donne l'exercice." if exercice.nil?

            return arguments["cloturer"] ? cloture(exercice) : suppression(exercice)
          end

          attributs = attributs!(arguments, exercice)
          raise Error, "Rien à changer." if exercice && attributs.empty?

          apres = simuler { ecrire(exercice&.id, attributs) }
          resume = exercice ? "Corriger : #{ligne_exercice(exercice)}\nAprès : #{apres}" : "Nouvel exercice : #{apres}"
          Plan.new(resume: resume, empreinte: [exercice && etat_de(exercice), attributs.transform_values(&:to_s).sort],
                   donnees: { id: exercice&.id, attributs: attributs })
        end

        def cloture(exercice)
          raise Error, "Cet exercice est déjà clôturé." if exercice.closed?

          attente = CashEntry.pending.in_period(exercice.starts_on, exercice.ends_on).count
          resume = ["Clôturer #{ligne_exercice(exercice)}",
                    "IRRÉVERSIBLE depuis Claude : ses #{exercice.journal_entries.count} écriture(s) se figent, plus rien ne s'y passe.",
                    ("⚠ #{attente} ligne(s) de trésorerie de cette période sont encore à affecter." if attente.positive?)].compact
          Plan.new(resume: resume.join("\n"), empreinte: [etat_de(exercice), "cloturer"], donnees: { id: exercice.id, geste: "cloturer" })
        end

        def suppression(exercice)
          raise Error, "Un exercice clôturé ne se supprime pas." if exercice.closed?
          raise Error, "Cet exercice porte des écritures : il ne se supprime pas." if exercice.journal_entries.exists?

          Plan.new(resume: "Supprimer #{ligne_exercice(exercice)}", empreinte: [etat_de(exercice), "supprimer"],
                   donnees: { id: exercice.id, geste: "supprimer" })
        end

        def appliquer(plan)
          d = plan.donnees
          case d[:geste]
          when "cloturer"
            exercice = FiscalYear.find(d[:id])
            metier! { exercice.close! }
            "Exercice clôturé : #{ligne_exercice(exercice)}. Ses écritures ne se corrigent plus que par contre-passation."
          when "supprimer"
            exercice = FiscalYear.find(d[:id])
            raise Error, (exercice.errors.full_messages.to_sentence.presence || "Cet exercice ne se supprime pas.") unless exercice.destroy

            "Exercice #{exercice.label} de #{exercice.legal_entity.name} supprimé."
          else
            "Exercice enregistré : #{ecrire(d[:id], d[:attributs])}"
          end
        end

        def ecrire(id, attributs)
          exercice = id ? FiscalYear.find(id) : FiscalYear.new(status: "open")
          metier! { exercice.update!(attributs) }
          ligne_exercice(exercice.reload)
        end

        def exercice!(arguments)
          texte = arguments["exercice"].to_s.strip.delete_prefix("#")
          if texte.match?(/\A\d{4}\z/) && arguments["entite"].present?
            entite = entite_meme_inactive!(arguments["entite"])
            return FiscalYear.find_by(legal_entity: entite, starts_on: Date.new(texte.to_i, 1, 1)..Date.new(texte.to_i, 12, 31)) ||
                   raise(Error, "#{entite.name} n'a pas d'exercice #{texte}.")
          end

          FiscalYear.includes(:legal_entity).find_by(id: id!(texte, "exercice")) ||
            raise(Error, "Aucun exercice ##{texte} (pour une année, donne aussi l'entité).")
        end

        def attributs!(arguments, exercice)
          a = {}
          a[:legal_entity_id] = entite_meme_inactive!(arguments["entite"]).id if arguments["entite"].present? && exercice.nil?
          a[:starts_on] = date!(arguments["debut"], "debut") if arguments["debut"].present?
          a[:ends_on] = date!(arguments["fin"], "fin") if arguments["fin"].present?
          return a if exercice
          raise Error, "Pour créer un exercice, donne l'entité." if a[:legal_entity_id].nil?

          a[:starts_on] ||= Date.current.beginning_of_year
          a[:ends_on] ||= a[:starts_on].end_of_year
          a
        end
      end
    end
  end
end
