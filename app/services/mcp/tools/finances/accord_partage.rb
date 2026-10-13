module Mcp
  module Tools
    module Finances
      # Comptabilité > Partages de revenus (RevenueShareAgreementsController
      # #create, #update, #deactivate et #reactivate). Un accord ne se supprime
      # pas : il se désactive, ses relevés passés restent lisibles.
      class AccordPartage < Ecriture
        include Commun

        PERIODES = { "trimestrielle" => "quarterly", "mensuelle" => "monthly" }.freeze

        tool "accord_partage",
             title: "Créer, corriger, désactiver un accord de partage de revenus",
             description: "L'accord qui reverse une part des réservations d'un hébergement à son bénéficiaire : " \
                          "hébergement, bénéficiaire (nom, email où part le relevé, IBAN, tiers), part en %, période " \
                          "(trimestrielle ou mensuelle), début, fin. `actif: false` le désactive, `true` le réactive. " \
                          "Les accords : partages_revenus.",
             schema: {
               properties: {
                 accord: { type: %w[integer string], description: "Pour corriger : l'accord (#id, hébergement ou bénéficiaire). Absent : nouvel accord." },
                 hebergement: { type: "string", description: "L'hébergement partagé (nom)." },
                 beneficiaire: { type: "string", description: "Nom du bénéficiaire." },
                 email: { type: "string", description: "Email du bénéficiaire, ou chaîne vide." },
                 iban: { type: "string", description: "IBAN du bénéficiaire, ou chaîne vide." },
                 tiers: { type: "string", description: "Le tiers comptable du bénéficiaire (nom), ou « aucun »." },
                 part: { type: "integer", description: "Part reversée, en % (1 à 100). Défaut à la création : 50." },
                 periode: { type: "string", enum: PERIODES.keys, description: "Défaut à la création : trimestrielle." },
                 debut: DATE.merge(description: "Début de l'accord. Défaut à la création : le 1er janvier."),
                 fin: DATE.merge(description: "Fin de l'accord. Chaîne vide pour l'effacer."),
                 actif: { type: "boolean" }
               }
             }

        private

        def planifier(arguments)
          accord = arguments["accord"].present? ? accord_partage!(arguments["accord"]) : nil
          attributs = attributs!(arguments, accord)
          raise Error, "Rien à changer." if accord && attributs.empty?

          apres = simuler { ecrire(accord&.id, attributs) }
          resume = accord ? "Corriger : #{ligne_accord(accord)}\nAprès : #{apres}" : "Nouvel accord : #{apres}"
          Plan.new(resume: resume, empreinte: [accord && etat_de(accord), attributs.transform_values(&:to_s).sort],
                   donnees: { id: accord&.id, attributs: attributs })
        end

        def appliquer(plan)
          "Accord enregistré : #{ecrire(plan.donnees[:id], plan.donnees[:attributs])}"
        end

        def ecrire(id, attributs)
          accord = id ? RevenueShareAgreement.find(id) : RevenueShareAgreement.new
          metier! { accord.update!(attributs) }
          ligne_accord(accord.reload)
        end

        def attributs!(arguments, accord)
          a = {}
          a[:lodging_id] = par_nom!(Lodging.all, arguments["hebergement"], "hébergement").id if arguments["hebergement"].present?
          a[:beneficiary_name] = arguments["beneficiaire"].to_s.strip if arguments["beneficiaire"].present?
          a[:beneficiary_email] = arguments["email"].to_s.strip.presence if arguments.key?("email")
          a[:beneficiary_iban] = arguments["iban"].to_s.strip.presence if arguments.key?("iban")
          if arguments["tiers"].present?
            a[:beneficiary_third_party_id] = arguments["tiers"].to_s.strip.casecmp?("aucun") ? nil : tiers!(arguments["tiers"]).id
          end
          a[:share_percent] = arguments["part"].to_i if arguments["part"].present?
          if arguments["periode"].present?
            a[:period] = PERIODES[arguments["periode"]] || raise(Error, "periode : #{PERIODES.keys.join(', ')}.")
          end
          a[:starts_on] = date!(arguments["debut"], "debut") if arguments["debut"].present?
          a[:ends_on] = date_ou_nil(arguments["fin"], "fin") if arguments.key?("fin")
          a[:active] = arguments["actif"] unless arguments["actif"].nil?
          return a if accord

          manquants = { lodging_id: "hebergement", beneficiary_name: "beneficiaire" }.reject { |champ, _| a[champ].present? }
          raise Error, "Pour créer un accord, donne : #{manquants.values.join(', ')}." if manquants.any?

          { share_percent: 50, period: "quarterly", starts_on: Date.current.beginning_of_year }.merge(a)
        end
      end
    end
  end
end
