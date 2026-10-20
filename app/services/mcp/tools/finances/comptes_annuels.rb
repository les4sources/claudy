module Mcp
  module Tools
    module Finances
      # Comptabilité › États › Comptes annuels (Finance::AnnualAccountsController) :
      # le bilan, le compte de résultats et l'affectation d'un exercice au
      # schéma abrégé de la BNB, avec l'exercice précédent.
      class ComptesAnnuels < Base
        include Commun

        tool "comptes_annuels",
             title: "Bilan et compte de résultats (schéma BNB)",
             description: "Les comptes annuels d'un exercice au schéma abrégé de la BNB (associations et fondations, " \
                          "ou sociétés) : bilan (actif, passif), compte de résultats (marge brute, résultat " \
                          "d'exploitation, financier, de l'exercice) et affectation, avec l'exercice précédent. " \
                          "Les comptes de tiers et de trésorerie vont du côté de leur solde. `detail` ajoute les " \
                          "comptes de chaque rubrique. Les avertissements disent ce qui rend les chiffres provisoires.",
             schema: {
               properties: {
                 entite: ENTITE.merge(description: "Défaut : la fondation."),
                 annee: { type: "integer", description: "L'exercice (année de début). Défaut : l'exercice en cours." },
                 detail: { type: "boolean", description: "Ajouter les comptes sous chaque rubrique." }
               }
             }

        def call(arguments)
          entite = arguments["entite"].present? ? entite_meme_inactive!(arguments["entite"]) : fondation!
          exercice = exercice!(entite, arguments["annee"])
          comptes = ::Accounting::AnnualAccounts.new(exercice)
          detail = arguments["detail"]
          precedent = comptes.previous_year&.label

          sortie = ["Comptes annuels #{exercice.label} · #{entite.name} · #{comptes.schema_label}" \
                    "#{" · entre parenthèses : #{precedent}" if precedent}",
                    *comptes.warnings.map { |w| "⚠ #{w}" },
                    "", "BILAN — ACTIF", *lignes(comptes.assets, detail),
                    "Total de l'actif · #{montants(comptes.total_assets_cents, comptes.previous_total_assets_cents)}",
                    "", "BILAN — PASSIF", *lignes(comptes.liabilities, detail),
                    "Total du passif · #{montants(comptes.total_liabilities_cents, comptes.previous_total_liabilities_cents)}",
                    "", "COMPTE DE RÉSULTATS", *lignes(comptes.income_statement, detail),
                    "", "AFFECTATION", *lignes(comptes.appropriation, false)]
          sortie.join("\n")
        end

        private

        def fondation! = LegalEntity.actives.find_by(form: "foundation") || raise(Error, "Donne l'entité.")

        def exercice!(entite, annee)
          if annee.present?
            return entite.fiscal_years.find { |y| y.starts_on.year == annee.to_i } ||
                   raise(Error, "#{entite.name} n'a pas d'exercice #{annee}.")
          end

          entite.fiscal_year_for(Date.current) || entite.fiscal_years.max_by(&:starts_on) ||
            raise(Error, "#{entite.name} n'a aucun exercice.")
        end

        def lignes(rows, detail)
          rows.flat_map do |row|
            next [] if row.blank? && row.level.positive? && !row.section?
            next ["— #{row.label}"] if row.section?

            entete = "#{'  ' * row.level}#{"[#{row.code}] " if row.code.present?}#{row.label} · " \
                     "#{montants(row.amount_cents, row.previous_cents)}"
            comptes = detail ? row.accounts.map { |c, n, p| "#{'  ' * (row.level + 2)}#{c.code} #{c.name} · #{montants(n, p)}" } : []
            [entete, *comptes]
          end
        end

        def montants(courant, precedent)
          precedent.nil? ? euros(courant.to_i) : "#{euros(courant.to_i)} (#{euros(precedent.to_i)})"
        end
      end
    end
  end
end
