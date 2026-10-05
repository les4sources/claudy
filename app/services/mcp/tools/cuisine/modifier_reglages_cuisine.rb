module Mcp
  module Tools
    module Cuisine
      # Paramètres > Cuisine (Kitchen::SettingsController#update). Seuls les
      # champs donnés changent ; le reste garde sa valeur.
      class ModifierReglagesCuisine < Ecriture
        include Commun

        REGLAGE_FAMILLE = {
          type: "object", additionalProperties: false,
          properties: {
            proposee: { type: "boolean", description: "false retire la famille de l'offre (formulaire client et saisie)." },
            responsable: { type: "string", description: "Responsable par défaut (nom), ou « aucun »." },
            plafond: { type: %w[integer string], description: "Convives au-delà desquels on avertit ; « aucun » pour aucun." },
            delai: { type: %w[integer string], description: "Jours de délai d'usage ; « aucun » pour aucun." }
          }
        }.freeze

        tool "modifier_reglages_cuisine",
             title: "Modifier les réglages de la cuisine",
             description: "Change les réglages de Paramètres > Cuisine : familles proposées, responsable par défaut, " \
                          "plafond de convives et délai d'usage (ils avertissent, ne bloquent jamais), email de " \
                          "coordination qui reçoit les refus, comptes de charge suivis par le bilan.",
             schema: {
               properties: {
                 repas: REGLAGE_FAMILLE, buffet: REGLAGE_FAMILLE, apero: REGLAGE_FAMILLE,
                 email_coordination: { type: "string" },
                 comptes_charges: { type: "array", items: { type: "string" },
                                    description: "Codes des comptes de charge (classe 6, actifs) à suivre, ex. [\"600005\", \"600006\"]. Remplace la liste." }
               }
             }

        private

        def planifier(arguments)
          reglages = {}
          Kitchen::Config.family_keys.each do |famille|
            (arguments[famille] || {}).each do |champ, valeur|
              reglages.merge!(reglage_famille(famille, champ, valeur))
            end
          end
          if arguments.key?("email_coordination")
            email = arguments["email_coordination"].to_s.strip
            raise Error, "email_coordination : adresse illisible « #{email} »." unless email.empty? || email.match?(URI::MailTo::EMAIL_REGEXP)

            reglages["kitchen.coordinator_email"] = email
          end
          reglages[Kitchen::Config::EXPENSE_ACCOUNTS_KEY] = comptes(arguments["comptes_charges"]) if arguments.key?("comptes_charges")

          changes = reglages.reject { |cle, valeur| Setting[cle].to_s == valeur }
          raise Error, "Rien à changer." if changes.empty?

          resume = changes.map { |cle, valeur| "- #{cle} : « #{lisible(cle, Setting[cle])} » → « #{lisible(cle, valeur)} »" }
          Plan.new(resume: "Réglages de la cuisine :\n#{resume.join("\n")}",
                   empreinte: changes.map { |cle, valeur| [cle, Setting[cle], valeur] }, donnees: { changes: changes })
        end

        def appliquer(plan)
          plan.donnees[:changes].each { |cle, valeur| Setting.set(cle, valeur) }
          "Réglages enregistrés (#{plan.donnees[:changes].size})."
        end

        def reglage_famille(famille, champ, valeur)
          cle = "kitchen.#{famille}"
          aucun = valeur.to_s.strip.match?(/\A(|aucun|aucune|personne|null)\z/i)
          case champ
          when "proposee" then { "#{cle}.enabled" => valeur ? "1" : "0" }
          when "responsable" then { "#{cle}.default_human_id" => aucun ? "" : membre!(valeur).id.to_s }
          when "plafond", "delai"
            nombre = aucun ? "" : Integer(valeur.to_s, exception: false)
            raise Error, "#{famille}.#{champ} : un nombre entier, ou « aucun »." if nombre.nil? || (nombre.is_a?(Integer) && nombre.negative?)

            { "#{cle}.#{champ == 'plafond' ? 'max_people' : 'lead_days'}" => nombre.to_s }
          else raise Error, "Réglage inconnu : #{famille}.#{champ}."
          end
        end

        def comptes(codes)
          codes = Array(codes).map { |c| c.to_s.strip }.compact_blank
          trouves = Kitchen::Config.selectable_expense_accounts.where(code: codes).to_a
          inconnus = codes - trouves.map(&:code)
          raise Error, "Comptes de charge introuvables ou inactifs : #{inconnus.join(', ')}." if inconnus.any?

          trouves.map(&:id).sort.join(",")
        end

        def lisible(cle, valeur)
          return "" if valeur.blank?
          return Human.unscoped.find_by(id: valeur)&.name || valeur if cle.end_with?("default_human_id")
          return GeneralAccount.where(id: valeur.split(",")).map(&:code).sort.join(", ") if cle == Kitchen::Config::EXPENSE_ACCOUNTS_KEY

          valeur
        end
      end
    end
  end
end
