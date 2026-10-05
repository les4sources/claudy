module Mcp
  module Tools
    module Sejours
      # Le formulaire d'édition du séjour (`Stays::AdminUpdater`) : on part du
      # séjour tel qu'il est, et seuls les champs fournis changent.
      class ModifierSejour < Ecriture
        include Commun
        include Composition

        tool "modifier_sejour",
             title: "Modifier un séjour",
             description: "Modifie un séjour comme son formulaire d'édition : dates, gîte ou chambres, personnes, " \
                          "espaces, camping, repas, activités, draps, catégorie, client rattaché, prix imposé, " \
                          "statut de facture. Seuls les champs donnés changent ; une liste donnée (repas, salles, " \
                          "activités) REMPLACE l'existante. Aucun email au client ; un repas ajouté ou changé " \
                          "prévient la cuisine. Le statut se change avec changer_statut_sejour.",
             schema: {
               properties: { sejour: SEJOUR, client: CLIENT.merge(description: "Rattacher le séjour à un autre client.") }
                 .merge(Composition::PROPRIETES)
                 .merge(prix_impose: { type: %w[number string], description: "Prix total imposé en euros ; « aucun » revient au devis." },
                        facture: { type: "string", enum: %w[aucune a_fournir envoyee], description: "Statut de la facture." },
                        forcer_dispo: { type: "boolean", description: "Enregistrer même si le gîte n'est pas libre (surbooking)." }),
               required: %w[sejour]
             }

        FACTURES = { "aucune" => nil, "a_fournir" => "requested", "envoyee" => "sent" }.freeze
        CHAMPS_FORMULAIRE = (Composition::PROPRIETES.keys.map(&:to_s) + %w[client prix_impose]).freeze

        private

        def planifier(arguments)
          stay = sejour!(arguments["sejour"])
          composition = arguments.keys.intersect?(CHAMPS_FORMULAIRE)
          facture = arguments.key?("facture") ? FACTURES.fetch(arguments["facture"]) { raise Error, "facture : aucune, a_fournir ou envoyee." } : :inchangee
          raise Error, "Rien à modifier : donne au moins un champ." if !composition && facture == :inchangee

          avant = photo(stay)
          apres = simuler do
            changer(stay.id, arguments, facture)
            photo(Stay.find(stay.id))
          end
          raise Error, "Ces changements ne modifient rien au séjour ##{stay.id}." if avant.except(:avertissements) == apres.except(:avertissements)

          Plan.new(
            resume: "Séjour ##{stay.id} — #{nom_sejour(stay)}\n\nAvant : #{decrire(avant)}\nAprès : #{decrire(apres)}" \
                    "#{"\n\n#{apres[:avertissements].join("\n")}" if apres[:avertissements].any?}",
            empreinte: [etat(stay), arguments_signes(arguments)],
            donnees: { stay_id: stay.id, arguments: arguments, facture: facture }
          )
        end

        def appliquer(plan)
          stay = changer(plan.donnees[:stay_id], plan.donnees[:arguments], plan.donnees[:facture])
          ["Séjour ##{stay.id} modifié : #{decrire(photo(stay))}", *avertissements_cuisine(stay)].join("\n")
        end

        def changer(stay_id, arguments, facture)
          stay = Stay.find(stay_id)
          @avertissements = []
          if arguments.keys.intersect?(CHAMPS_FORMULAIRE)
            draft = brouillon(arguments, base: Stays::DraftReconstructor.new(stay).to_draft.to_h)
            if arguments["client"].present?
              client = client!(arguments["client"])
              draft.customer_id = client.id
              %i[first_name last_name email phone customer_type organization_name].each { |c| draft.public_send("#{c}=", client.public_send(c)) }
            end
            prix = arguments.key?("prix_impose") ? prix_impose(arguments["prix_impose"]) : stay.price_override_cents
            updater = Stays::AdminUpdater.new(stay: stay, draft: draft, skip_availability: arguments["forcer_dispo"] == true,
                                              user: user, price_override_cents: prix)
            raise Error, updater.error_message(default: "Le séjour n'a pas pu être modifié.") unless updater.run

            @avertissements = [updater.availability_warning, updater.space_warning].compact
          end
          stay.update!(invoice_status: facture) unless facture == :inchangee
          stay.reload
        end

        def photo(stay)
          stay = Stay.includes(:customer, :meal_orders, :linen_orders, :experience_bookings, stay_items: :bookable).find(stay.id)
          {
            client: ligne_client(stay.customer), dates: dates(stay), total: stay.total_amount_cents,
            prix_impose: stay.price_override_cents, categorie: stay.category_label, facture: stay.invoice_status_label,
            composition: stay.decorate.composition_summary,
            lignes: stay.stay_items.filter_map(&:bookable).map { |b| "#{stay.decorate.item_label(b)} #{euros(b.try(:price_cents))}" }.sort +
                    stay.meal_orders.active.map { |r| "#{r.label} #{r.date} #{r.people} pers." }.sort,
            avertissements: (@avertissements || []) + avertissements_cuisine(stay)
          }
        end

        def decrire(photo)
          "#{photo[:dates]} · #{photo[:client]} · total #{euros(photo[:total])}#{' (imposé)' if photo[:prix_impose]} · " \
            "#{photo[:composition]} · catégorie #{photo[:categorie] || 'aucune'} · facture #{photo[:facture]}" \
            "#{"\n  #{photo[:lignes].join("\n  ")}" if photo[:lignes].any?}"
        end
      end
    end
  end
end
