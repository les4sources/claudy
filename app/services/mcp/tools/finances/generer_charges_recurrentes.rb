module Mcp
  module Tools
    module Finances
      # Finances > Charges récurrentes (RecurringChargesController#preview et
      # #generate) : poser les charges fixes d'un mois (loyers, charges,
      # cotisations) sur les comptes courants.
      class GenererChargesRecurrentes < Ecriture
        include Commun

        tool "generer_charges_recurrentes",
             title: "Générer les charges récurrentes du mois",
             description: "Pose sur les comptes courants les charges récurrentes actives d'un mois (une écriture par " \
                          "compte et par charge, datée de la fin du mois). Rejouable : ce qui existe déjà n'est pas " \
                          "recréé. L'aperçu liste ce qui sera créé, ce qui existe et ce qui est ignoré (et pourquoi). " \
                          "À faire avant d'émettre les décomptes.",
             schema: { properties: { mois: MOIS.merge(description: "Mois, AAAA-MM. Défaut : le mois en cours.") } }

        private

        def planifier(arguments)
          mois = mois!(arguments["mois"], defaut: Date.current.beginning_of_month)
          rapport = metier! { ::Finance::GenerateRecurringCharges.new(month: mois, dry_run: true).run! }
          raise Error, "Rien à générer pour #{nom_mois(mois)} : aucune charge active." unless rapport.any?

          crees = rapport.created.map do |ligne|
            "  #{ligne[:account].code} #{ligne[:account].name} : #{ligne[:label]} #{euros(ligne[:amount_cents])} (#{AccountEntry::FLOW_LABELS.fetch(ligne[:flow], ligne[:flow])})"
          end
          ignores = rapport.skipped.map { |s| "  #{s[:account]&.code} #{s[:charge].label} : #{s[:reason]}" }
          resume = ["Charges de #{nom_mois(mois)} : #{rapport.created_count} écriture(s) à créer pour #{euros(rapport.total_cents)}, " \
                    "#{rapport.existing.size} déjà présente(s), #{rapport.skipped.size} ignorée(s)."]
          resume << crees.join("\n") if crees.any?
          resume << "Ignorées :\n#{ignores.join("\n")}" if ignores.any?
          Plan.new(resume: resume.join("\n"),
                   empreinte: [mois.iso8601, rapport.created.map { |l| [l[:idempotency_key], l[:amount_cents]] }],
                   donnees: { mois: mois.iso8601 })
        end

        def appliquer(plan)
          mois = Date.iso8601(plan.donnees[:mois])
          rapport = metier! { ::Finance::GenerateRecurringCharges.new(month: mois, whodunnit: whodunnit).run! }
          "#{rapport.created_count} écriture(s) créée(s) pour #{nom_mois(mois)} (#{euros(rapport.total_cents)}), " \
            "#{rapport.existing.size} déjà présente(s), #{rapport.skipped.size} ignorée(s)."
        end
      end
    end
  end
end
