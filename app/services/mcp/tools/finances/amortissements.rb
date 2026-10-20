module Mcp
  module Tools
    module Finances
      # Comptabilité › États › Immobilisations (Finance::FixedAssetsController
      # #depreciate et #cancel_depreciation) : passer les dotations d'un
      # exercice, ou en annuler une pour la refaire.
      class Amortissements < Ecriture
        include Commun

        tool "amortissements",
             title: "Passer ou annuler les dotations aux amortissements",
             description: "`passer` : pour un exercice ouvert, une écriture par immobilisation au dernier jour, compte " \
                          "de dotation (630100) au débit avec le pôle du bien, compte d'amortissements au crédit ; seules " \
                          "les dotations manquantes. `annuler` : contre-passe la dotation d'un bien (`dotation`, rendu " \
                          "par immobilisations) sur un exercice ouvert, pour la refaire après correction.",
             schema: {
               properties: {
                 geste: { type: "string", enum: %w[passer annuler] },
                 entite: ENTITE.merge(description: "Pour passer. Défaut : la fondation."),
                 annee: { type: "integer", description: "Pour passer : l'exercice (année de début). Défaut : l'exercice en cours." },
                 dotation: { type: %w[integer string], description: "Pour annuler : la dotation (#12)." }
               },
               required: %w[geste]
             }

        private

        def planifier(arguments)
          arguments["geste"] == "annuler" ? annulation(arguments) : passation(arguments)
        end

        def passation(arguments)
          entite = arguments["entite"].present? ? entite!(arguments["entite"]) : LegalEntity.actives.find_by(form: "foundation")
          raise Error, "Donne l'entité." if entite.nil?

          exercice = if arguments["annee"].present?
                       entite.fiscal_years.find { |y| y.starts_on.year == arguments["annee"].to_i }
                     else
                       entite.fiscal_year_for(Date.current)
                     end
          raise Error, "#{entite.name} n'a pas cet exercice." if exercice.nil?
          raise Error, "L'exercice #{exercice.label} est clôturé : ses dotations sont définitives." if exercice.closed?

          lignes = ::Accounting::PostDepreciations.new(fiscal_year: exercice).rows
          raise Error, "Aucune dotation à passer sur #{exercice.label}." if lignes.empty?

          resume = ["Passer #{lignes.size} dotation(s) au #{exercice.ends_on} (#{entite.name}) : #{euros(lignes.sum(&:amount_cents))}",
                    *lignes.map do |l|
                      "  ##{l.asset.id} #{l.asset.name} · #{l.asset.expense_account.code} / #{l.asset.depreciation_account.code} · " \
                        "#{euros(l.amount_cents)}#{' (rattrapage : plus qu’une annuité)' if l.catch_up?}"
                    end]
          Plan.new(resume: resume.join("\n"), empreinte: ["passer", exercice.id, lignes.map { |l| [l.asset.id, l.amount_cents] }],
                   donnees: { geste: "passer", id: exercice.id })
        end

        def annulation(arguments)
          dotation = FixedAssetDepreciation.find_by(id: id!(arguments["dotation"], "dotation")) ||
                     raise(Error, "Aucune dotation ##{arguments['dotation']}.")
          raise Error, "L'exercice #{dotation.fiscal_year.label} est clôturé : cette dotation est définitive." if dotation.fiscal_year.closed?

          Plan.new(resume: "Contre-passer la dotation #{dotation.fiscal_year.label} de « #{dotation.fixed_asset.name} » (#{euros(dotation.amount_cents)}).",
                   empreinte: ["annuler", etat_de(dotation)], donnees: { geste: "annuler", id: dotation.id })
        end

        def appliquer(plan)
          if plan.donnees[:geste] == "annuler"
            dotation = FixedAssetDepreciation.find(plan.donnees[:id])
            metier! { ::Accounting::CancelDepreciation.new(depreciation: dotation, whodunnit: whodunnit).run! }
            "Dotation contre-passée : elle peut être repassée avec `passer`."
          else
            exercice = FiscalYear.find(plan.donnees[:id])
            lignes = metier! { ::Accounting::PostDepreciations.new(fiscal_year: exercice, whodunnit: whodunnit).run! }
            "#{lignes.size} dotation(s) passée(s) au #{exercice.ends_on} : #{euros(lignes.sum(&:amount_cents))}."
          end
        end
      end
    end
  end
end
