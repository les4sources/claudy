module Mcp
  module Tools
    module Sejours
      # Les services annexes d'un séjour (Michael, 2026-10-23) : prêt d'un set
      # de disc-golf, et ce qui viendra. Une ligne = un libellé et un montant,
      # préremplis depuis le catalogue des services, qui s'ajoutent au total
      # du séjour (prix imposé compris). Aucun email ne part.
      class ServicesAnnexesSejour < Ecriture
        include Commun

        tool "services_annexes_sejour",
             title: "Ajouter ou retirer un service annexe d'un séjour",
             description: "Ajoute une ligne de service annexe à un séjour (ex. prêt d'un set de disc-golf) : un libellé et " \
                          "un montant, qui s'ajoutent au total du séjour, prix imposé compris. `service` reprend un service " \
                          "du catalogue (nom ou #id) : son nom et son prix servent quand libellé ou montant manquent. " \
                          "Avec action « retirer », retire la ligne `ligne` (#id rendu par fiche_sejour). Aucun email au client. " \
                          "Sans séjour ni action, liste le catalogue des services.",
             schema: {
               properties: {
                 sejour: SEJOUR,
                 action: { type: "string", enum: %w[ajouter retirer catalogue], description: "ajouter (défaut), retirer, ou catalogue (liste des services, rien n'est écrit)." },
                 service: { type: %w[integer string], description: "Service du catalogue : #id ou nom (facultatif)." },
                 libelle: { type: "string", description: "Libellé de la ligne (sinon, le nom du service)." },
                 montant: { type: %w[number string], description: "Montant en euros, TVAC (sinon, le prix du service). 0 est un vrai montant." },
                 ligne: { type: %w[integer string], description: "Pour retirer : l'identifiant de la ligne." }
               }
             }

        def call(arguments)
          return catalogue if arguments["action"] == "catalogue" || arguments["sejour"].blank?

          super
        end

        private

        def catalogue
          services = Service.ordered.includes(:general_account).to_a
          return "Aucun service au catalogue (/services)." if services.empty?

          lignes = services.map do |service|
            compte = service.general_account ? ", compte #{service.general_account.code}" : ""
            "- ##{service.id} #{service.name} : #{service.price_cents ? euros(service.price_cents) : 'sans prix'}#{compte}"
          end
          "Catalogue des services :\n#{lignes.join("\n")}"
        end

        def planifier(arguments)
          stay = sejour!(arguments["sejour"])
          arguments["action"] == "retirer" ? planifier_retrait(stay, arguments) : planifier_ajout(stay, arguments)
        end

        def planifier_ajout(stay, arguments)
          service = service!(arguments["service"]) if arguments["service"].present?
          libelle = arguments["libelle"].to_s.strip.presence || service&.name
          montant = montant(arguments["montant"]) || service&.price_cents
          raise Error, "Indique un libellé, ou un service du catalogue." if libelle.blank?
          raise Error, "Indique un montant (le service « #{service&.name} » n'a pas de prix)." if montant.nil?

          Plan.new(
            resume: "#{ligne_sejour(stay)}\nAjout du service annexe « #{libelle} » : #{euros(montant)}" \
                    "#{" (repris du service ##{service.id})" if service}.\n" \
                    "Total du séjour après : #{euros(stay.total_amount_cents.to_i + montant)}. Aucun email au client.",
            empreinte: [etat(stay), "ajouter", libelle, montant, service&.id],
            donnees: { stay_id: stay.id, libelle: libelle, montant: montant, service_id: service&.id }
          )
        end

        def planifier_retrait(stay, arguments)
          ligne = stay.service_lines.find_by(id: identifiant!(arguments["ligne"], "ligne")) ||
                  raise(Error, "Aucune ligne de service annexe #{arguments['ligne']} sur le séjour ##{stay.id}.")

          Plan.new(
            resume: "#{ligne_sejour(stay)}\nRetrait du service annexe ##{ligne.id} « #{ligne.label} » : #{euros(ligne.amount_cents)}.\n" \
                    "Total du séjour après : #{euros(stay.total_amount_cents.to_i - ligne.amount_cents)}.",
            empreinte: [etat(stay), "retirer", ligne.id],
            donnees: { stay_id: stay.id, ligne_id: ligne.id }
          )
        end

        def appliquer(plan)
          stay = Stay.find(plan.donnees[:stay_id])
          if plan.donnees[:ligne_id]
            ligne = stay.service_lines.find(plan.donnees[:ligne_id])
            Stays::RemoveServiceLine.new(line: ligne).run!
            "Service annexe « #{ligne.label} » retiré du séjour ##{stay.id}. Total : #{euros(stay.reload.total_amount_cents)}."
          else
            service = Service.find_by(id: plan.donnees[:service_id])
            ligne = Stays::AddServiceLine.new(stay: stay).run!(label: plan.donnees[:libelle], amount_cents: plan.donnees[:montant], service: service)
            "Service annexe ##{ligne.id} « #{ligne.label} » ajouté au séjour ##{stay.id}. Total : #{euros(stay.reload.total_amount_cents)}."
          end
        end

        def service!(reference)
          texte = reference.to_s.strip
          if texte.delete("#").match?(/\A\d+\z/)
            return Service.find_by(id: texte.delete("#")) || raise(Error, "Aucun service #{texte} au catalogue.")
          end

          candidats = Service.where("name ILIKE ?", "%#{Service.sanitize_sql_like(texte)}%").ordered.to_a
          return candidats.first if candidats.size == 1
          raise Error, "Aucun service ne correspond à « #{texte} »." if candidats.empty?

          raise Error, "Plusieurs services correspondent à « #{texte} » : #{candidats.map { |s| "##{s.id} #{s.name}" }.join(', ')}."
        end

        def montant(valeur)
          return nil if valeur.nil? || valeur.to_s.strip.empty?

          texte = valeur.to_s.strip.delete(" €").tr(",", ".")
          raise Error, "Montant illisible : « #{valeur} »." unless texte.match?(/\A\d+(\.\d{1,2})?\z/)

          (BigDecimal(texte) * 100).to_i
        end
      end
    end
  end
end
