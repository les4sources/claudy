module Mcp
  module Tools
    module Finances
      # Comptabilité > Exercices (FiscalYearsController #create, #update,
      # #close, #reopen et #destroy). Clôturer est le geste qui fige : le
      # résultat est affecté, les écritures se verrouillent et l'à-nouveau de
      # l'exercice suivant est posé (`Accounting::CloseFiscalYear`).
      class Exercice < Ecriture
        include Commun

        tool "exercice",
             title: "Créer, corriger, clôturer ou supprimer un exercice comptable",
             description: "L'exercice d'une entité : dates de début et de fin (sans chevaucher un autre exercice de la " \
                          "même entité). `cloturer` : affecte le résultat (bénéfice 693 → 140, perte 140 → 793, OD au " \
                          "dernier jour), verrouille toutes les écritures, clôture, puis pose l'à-nouveau de l'exercice " \
                          "suivant au 1er jour (classes 1 à 5, par compte et par tiers ; l'exercice suivant est créé s'il " \
                          "manque). On clôture dans l'ordre des années. `a_nouveau` : `poser` (défaut, refusé s'il en " \
                          "existe déjà un), `remplacer` (contre-passe l'existant) ou `aucun`. Plus rien ne s'y passe " \
                          "ensuite, sauf par contre-passation : dis-le avant qu'il accepte. `rouvrir` (motif obligatoire) : " \
                          "seulement le dernier exercice clôturé de l'entité ; contre-passe l'affectation et l'à-nouveau. " \
                          "`supprimer` retire un exercice ouvert et vide. Les exercices : parametrage_compta exercices ; " \
                          "le bilan : comptes_annuels.",
             schema: {
               properties: {
                 exercice: { type: %w[integer string], description: "Pour corriger, clôturer ou supprimer : l'exercice (#id, ou l'année avec `entite`). Absent : nouvel exercice." },
                 entite: ENTITE.merge(description: "L'entité de l'exercice (à la création, ou pour le désigner par son année)."),
                 debut: DATE.merge(description: "Défaut à la création : le 1er janvier de l'année en cours."),
                 fin: DATE.merge(description: "Défaut à la création : le 31 décembre de l'année de début."),
                 cloturer: { type: "boolean" },
                 a_nouveau: { type: "string", enum: %w[poser remplacer aucun], description: "À la clôture : que faire de l'à-nouveau de l'exercice suivant. Défaut : poser." },
                 rouvrir: { type: "boolean", description: "Rouvrir le dernier exercice clôturé de l'entité. Exige `motif`." },
                 supprimer: { type: "boolean" }
               }
             }

        private

        def planifier(arguments)
          exercice = arguments["exercice"].present? ? exercice!(arguments) : nil
          if arguments["cloturer"] || arguments["supprimer"] || arguments["rouvrir"]
            raise Error, "Donne l'exercice." if exercice.nil?
            return cloture(exercice, arguments["a_nouveau"]) if arguments["cloturer"]

            return arguments["rouvrir"] ? reouverture(exercice) : suppression(exercice)
          end

          attributs = attributs!(arguments, exercice)
          raise Error, "Rien à changer." if exercice && attributs.empty?

          apres = simuler { ecrire(exercice&.id, attributs) }
          resume = exercice ? "Corriger : #{ligne_exercice(exercice)}\nAprès : #{apres}" : "Nouvel exercice : #{apres}"
          Plan.new(resume: resume, empreinte: [exercice && etat_de(exercice), attributs.transform_values(&:to_s).sort],
                   donnees: { id: exercice&.id, attributs: attributs })
        end

        A_NOUVEAU = { "poser" => "generate", "remplacer" => "replace", "aucun" => "none" }.freeze

        def cloture(exercice, a_nouveau)
          mode = A_NOUVEAU.fetch(a_nouveau.presence || "poser") { raise Error, "a_nouveau : poser, remplacer ou aucun." }
          apercu = ::Accounting::CloseFiscalYear.new(fiscal_year: exercice, opening: mode).preview
          raise Error, apercu.blockers.join("\n") if apercu.blockers.any?

          resume = ["Clôturer #{ligne_exercice(exercice)}",
                    "Résultat : #{solde_resultat(apercu.result_cents)}",
                    *apercu.appropriation.map { |l| "  Affectation · #{l.account.code} #{l.account.name} · #{l.debit_cents.positive? ? "débit #{euros(l.debit_cents)}" : "crédit #{euros(l.credit_cents)}"}" },
                    "Verrouille ses #{exercice.journal_entries.count} écriture(s) : IRRÉVERSIBLE depuis Claude, plus rien ne s'y passe.",
                    ligne_a_nouveau(apercu, mode),
                    *apercu.warnings.map { |w| "⚠ #{w}" }]
          Plan.new(resume: resume.join("\n"),
                   empreinte: [etat_de(exercice), "cloturer", mode, apercu.result_cents, apercu.opening_lines.size, apercu.opening_debit_cents],
                   donnees: { id: exercice.id, geste: "cloturer", mode: mode })
        end

        def ligne_a_nouveau(apercu, mode)
          return "À-nouveau #{apercu.next_year_label} : aucun (l'exercice suivant garde ses soldes d'ouverture)." if mode == "none"

          ["À-nouveau #{apercu.next_year_label} au 1er jour : #{apercu.opening_lines.size} ligne(s), " \
           "débit #{euros(apercu.opening_debit_cents)} = crédit #{euros(apercu.opening_credit_cents)}",
           ("(exercice #{apercu.next_year_label} créé)" unless apercu.next_year_exists),
           ("— remplace l'à-nouveau existant, contre-passé" if mode == "replace" && apercu.existing_opening)].compact.join(" ")
        end

        def solde_resultat(cents)
          return "nul" if cents.zero?

          cents.positive? ? "bénéfice de #{euros(cents)}" : "perte de #{euros(-cents)}"
        end

        def reouverture(exercice)
          reouvrir = ::Accounting::ReopenFiscalYear.new(fiscal_year: exercice, reason: @motif)
          refus = reouvrir.refusal
          raise Error, refus if refus

          Plan.new(resume: ["Rouvrir #{ligne_exercice(exercice)} — motif : #{@motif}",
                            "Contre-passe l'affectation du résultat et l'à-nouveau posés par la clôture, et déverrouille ses écritures."].join("\n"),
                   empreinte: [etat_de(exercice), "rouvrir", @motif], donnees: { id: exercice.id, geste: "rouvrir" })
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
            metier! { ::Accounting::CloseFiscalYear.new(fiscal_year: exercice, opening: d[:mode], whodunnit: whodunnit).run! }
            suivant = exercice.legal_entity.fiscal_years.find_by(starts_on: exercice.ends_on + 1)
            ["Exercice clôturé : #{ligne_exercice(exercice.reload)}. Résultat affecté, écritures verrouillées.",
             (suivant && d[:mode] != "none" ? "À-nouveau posé au #{suivant.starts_on} (exercice ##{suivant.id})." : nil)].compact.join(" ")
          when "rouvrir"
            exercice = FiscalYear.find(d[:id])
            metier! { ::Accounting::ReopenFiscalYear.new(fiscal_year: exercice, reason: @motif, whodunnit: whodunnit).run! }
            "Exercice rouvert : #{ligne_exercice(exercice.reload)}. Affectation et à-nouveau contre-passés."
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
