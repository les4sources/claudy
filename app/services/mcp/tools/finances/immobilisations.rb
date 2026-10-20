module Mcp
  module Tools
    module Finances
      # Comptabilité › États › Immobilisations (Finance::FixedAssetsController#index) :
      # le registre et les dotations d'un exercice.
      class Immobilisations < Base
        include Commun

        tool "immobilisations",
             title: "Registre des immobilisations",
             description: "Les immobilisations d'une entité : valeur, date, durée, amortissements cumulés, valeur " \
                          "nette, et pour un exercice la dotation passée ou à passer (linéaire, prorata au mois). " \
                          "Inscrire ou corriger un bien : immobilisation ; passer ou annuler les dotations : amortissements.",
             schema: {
               properties: {
                 entite: ENTITE.merge(description: "Défaut : la fondation."),
                 annee: { type: "integer", description: "L'exercice des dotations. Défaut : l'exercice en cours." }
               }
             }

        def call(arguments)
          entite = arguments["entite"].present? ? entite_meme_inactive!(arguments["entite"]) : fondation!
          exercice = if arguments["annee"].present?
                       entite.fiscal_years.find { |y| y.starts_on.year == arguments["annee"].to_i } ||
                         raise(Error, "#{entite.name} n'a pas d'exercice #{arguments['annee']}.")
                     else
                       entite.fiscal_year_for(Date.current)
                     end
          biens = FixedAsset.where(legal_entity: entite).includes(:general_account, :depreciation_account, :team, :depreciations).ordered.to_a
          return "Aucune immobilisation au registre de #{entite.name}." if biens.empty?

          sortie = ["Immobilisations de #{entite.name}#{" · dotations #{exercice.label}" if exercice}"]
          sortie += biens.map { |bien| ligne_bien(bien, exercice) }
          sortie << "Total · valeur #{euros(biens.sum(&:acquisition_cents))} · amorti #{euros(biens.sum(&:depreciated_cents))} · " \
                    "valeur nette #{euros(biens.sum(&:net_book_value_cents))}"
          if exercice
            a_passer = ::Accounting::PostDepreciations.new(fiscal_year: exercice)
            sortie << (a_passer.rows.any? ? "À passer sur #{exercice.label} : #{a_passer.rows.size} dotation(s), #{euros(a_passer.total_cents)}." : "Tout est doté sur #{exercice.label}.")
          end
          sortie.join("\n")
        end

        private

        def fondation! = LegalEntity.actives.find_by(form: "foundation") || raise(Error, "Donne l'entité.")

        def ligne_bien(bien, exercice)
          dotation = exercice && bien.depreciation_for(exercice)
          etat = if exercice.nil? then nil
                 elsif dotation then "dotation #{exercice.label} passée #{euros(dotation.amount_cents)} (dotation ##{dotation.id})"
                 elsif (du = bien.depreciation_due_cents(exercice)).positive? then "dotation #{exercice.label} à passer #{euros(du)}"
                 else "rien à doter sur #{exercice.label}"
                 end
          ["##{bien.id} #{bien.name}", "#{bien.general_account.code} / #{bien.depreciation_account.code}",
           "acquis le #{bien.acquired_on}", "valeur #{euros(bien.acquisition_cents)}", "#{bien.useful_life_years} ans",
           "amorti #{euros(bien.depreciated_cents)}", "valeur nette #{euros(bien.net_book_value_cents)}",
           (bien.team && "pôle #{bien.team.name}"), (bien.disposed_on && "sorti le #{bien.disposed_on}"), etat].compact.join(" · ")
        end
      end
    end
  end
end
