module Mcp
  module Tools
    module Sejours
      # « Nouveau séjour » côté équipe (`Reservations::Builder` en mode admin) :
      # une réservation prise au téléphone, par e-mail, ou saisie a posteriori.
      class CreerSejour < Ecriture
        include Commun
        include Composition

        NOUVEAU_CLIENT = {
          type: "object", additionalProperties: false,
          description: "Client à créer, quand il n'existe pas encore (vérifie d'abord avec chercher_clients).",
          properties: {
            prenom: { type: "string" }, nom: { type: "string" }, email: { type: "string" }, telephone: { type: "string" },
            organisation: { type: "string", description: "Pour une école, une association, une entreprise." }
          }
        }.freeze

        tool "creer_sejour",
             title: "Créer un séjour",
             description: "Crée un séjour comme le formulaire « Nouveau séjour » : client existant ou nouveau, gîte " \
                          "ou chambres, dates, espaces, camping, repas, activités, draps, statut. Créé « confirmed », " \
                          "il ENVOIE AU CLIENT l'email de confirmation ; « pending » (défaut) n'envoie rien. Des repas " \
                          "préviennent la cuisine. Calcule d'abord le prix avec devis_sejour si besoin.",
             schema: {
               properties: { client: CLIENT, nouveau_client: NOUVEAU_CLIENT }
                 .merge(Composition::PROPRIETES)
                 .merge(statut: { type: "string", enum: Stay::STATUSES_ADMIN_CREATABLE, description: "pending (défaut) ou confirmed." },
                        prix_impose: { type: %w[number string], description: "Prix total imposé en euros, à la place du devis." },
                        acompte_en_attente: { type: %w[number string],
                                              description: "Crée un paiement en attente de ce montant (euros). Aucun email." },
                        canal: { type: "string", enum: Stay::ADMIN_SELECTABLE_SOURCES, description: "manual (défaut) ou ota." },
                        plateforme: { type: "string", enum: Stay::OTA_PLATFORMS, description: "Pour une réservation venue d'une OTA." },
                        note_interne: { type: "string" },
                        note_publique: { type: "string", description: "Visible du client sur sa page de séjour." },
                        facture: { type: "string", enum: %w[a_fournir], description: "a_fournir si le client demande une facture." },
                        forcer_dispo: { type: "boolean", description: "Enregistrer même si le gîte n'est pas libre." }),
               required: %w[arrivee depart]
             }

        def self.transactionnel? = false

        private

        def planifier(arguments)
          draft = brouillon_client(arguments)
          statut_cible = arguments["statut"].presence || "pending"
          raise Error, "statut : pending ou confirmed." unless Stay::STATUSES_ADMIN_CREATABLE.include?(statut_cible)

          doublon!(draft)
          resultat = simuler do
            builder = construire(arguments, brouillon_client(arguments))
            raise Error, builder.error_message(default: "Le séjour n'a pas pu être créé.") unless builder.run

            stay = Stay.find(builder.stay.id)
            { ligne: ligne_sejour(stay), avertissements: [builder.availability_warning, builder.space_warning].compact + avertissements_cuisine(stay),
              email: statut_cible == "confirmed" ? email_client(stay) : nil }
          end
          email = if statut_cible != "confirmed" then "Aucun email au client (séjour en attente)."
                  elsif resultat[:email] then "Un email de confirmation partira à #{resultat[:email]}."
                  else "Aucun email ne pourra partir (client sans adresse exploitable)."
                  end

          Plan.new(
            resume: "Nouveau séjour : #{resultat[:ligne].sub(/\A#\d+\s+/, '')}\n#{lignes_devis(draft.quote)}" \
                    "#{"\nPrix imposé : #{euros(prix_impose(arguments['prix_impose']))}" if arguments['prix_impose'].present?}\n#{email}" \
                    "#{"\n#{resultat[:avertissements].join("\n")}" if resultat[:avertissements].any?}",
            empreinte: arguments_signes(arguments),
            donnees: { arguments: arguments }
          )
        end

        def appliquer(plan)
          arguments = plan.donnees[:arguments]
          builder = construire(arguments, brouillon_client(arguments))
          raise Error, builder.error_message(default: "Le séjour n'a pas pu être créé.") unless builder.run

          stay = builder.stay
          notes!(stay, arguments)
          stay.update!(invoice_status: "requested") if arguments["facture"] == "a_fournir"
          envoye = stay.status == "confirmed" && Stays::ConfirmationNotifier.call(stay)
          [
            "Séjour ##{stay.id} créé : #{ligne_sejour(stay.reload)}",
            ("Email de confirmation envoyé à #{stay.customer.email}." if envoye),
            builder.availability_warning, builder.space_warning, *avertissements_cuisine(stay)
          ].compact.join("\n")
        end

        def construire(arguments, draft)
          acompte = arguments["acompte_en_attente"].present? ? cents!(arguments["acompte_en_attente"], "acompte_en_attente").abs : nil
          Reservations::Builder.new(
            draft: draft, admin: true, status: arguments["statut"].presence || "pending",
            source: arguments["canal"].presence || "manual", platform: arguments["plateforme"].presence,
            price_override_cents: prix_impose(arguments["prix_impose"]), skip_availability: arguments["forcer_dispo"] == true,
            create_initial_payment: acompte.present?, initial_payment_amount_cents: acompte
          )
        end

        def brouillon_client(arguments)
          draft = brouillon(arguments)
          if arguments["client"].present?
            client = client!(arguments["client"])
            draft.customer_id = client.id
            %i[first_name last_name email phone customer_type organization_name].each { |c| draft.public_send("#{c}=", client.public_send(c)) }
          elsif (nouveau = arguments["nouveau_client"]).present?
            if nouveau["email"].present? && (existant = Customer.find_by(email: Customer.normalize_email(nouveau["email"])))
              raise Error, "Un client existe déjà avec cet e-mail : #{ligne_client(existant)}. Passe-le dans `client`."
            end

            draft.first_name = nouveau["prenom"].presence
            draft.last_name = nouveau["nom"].presence
            draft.email = nouveau["email"].presence
            draft.phone = nouveau["telephone"].presence
            draft.organization_name = nouveau["organisation"].presence
            draft.customer_type = draft.organization_name ? "organization" : "individual"
            draft.group_name ||= draft.organization_name
          else
            raise Error, "Précise le client : `client` (existant) ou `nouveau_client`."
          end
          draft
        end

        # Le même séjour créé deux fois (une confirmation rejouée) : on refuse.
        def doublon!(draft)
          clients = if draft.customer_id.present? then [draft.customer_id]
                    else Customer.where(first_name: draft.first_name, last_name: draft.last_name, organization_name: draft.organization_name)
                                 .where("created_at > ?", 1.hour.ago).pluck(:id)
                    end
          return if clients.empty?

          existant = Stay.where(customer_id: clients, arrival_date: draft.arrival_date, departure_date: draft.departure_date)
                         .where("created_at > ?", 1.hour.ago).first
          return unless existant

          raise Error, "Ce client a déjà un séjour créé à l'instant sur ces dates (##{existant.id}). Rien n'a été créé."
        end

        def notes!(stay, arguments)
          interne = arguments["note_interne"].to_s.strip
          if interne.present?
            stay.internal_notes = [Stays::InternalNote.to_html(interne), Stays::InternalNote.html_for(stay).presence].compact.join
          end
          stay.public_notes = Stays::InternalNote.to_html(arguments["note_publique"]) if arguments["note_publique"].present?
          stay.save! if stay.changed? || interne.present? || arguments["note_publique"].present?
        end
      end
    end
  end
end
