module Mcp
  module Tools
    module Cuisine
      # Le formulaire « Nouvelle demande » de la page Cuisine (grille à
      # plusieurs prestations, Kitchen::GridSubmission) : un séjour ou un
      # « pour qui », N prestations, une case cochée = un service.
      class CommanderPrestations < Ecriture
        include Commun
        include Sejours::Commun

        SERVICE = {
          type: "object", additionalProperties: false,
          properties: { date: DATE, moment: MOMENT },
          required: %w[date]
        }.freeze

        PRESTATION_A_COMMANDER = {
          type: "object", additionalProperties: false,
          properties: {
            type: TYPE,
            convives: { type: "integer", minimum: 1, description: "Nombre de personnes." },
            services: { type: "array", items: SERVICE, minItems: 1,
                        description: "Un service par date et moment (ex. trois midis = trois services)." },
            statut: STATUT.merge(description: "inquiry (demande d'info) ou requested (demande ferme, défaut) ou confirmed."),
            responsable: MEMBRE.merge(description: "Qui s'en charge. Défaut : le responsable de la famille. " \
                                                   "Pour un buffet ou un apéro, se charger vaut acceptation."),
            prix_par_personne: { type: %w[number string], description: "Prix imposé par personne, en euros. Défaut : le barème." },
            precisions: { type: "string", description: "Allergies, régimes, consignes." }
          },
          required: %w[type convives services]
        }.freeze

        tool "commander_prestations",
             title: "Commander des prestations à la cuisine",
             description: "Crée des demandes de cuisine (repas, goûters, buffets, apéros) pour un séjour, ou pour " \
                          "quelqu'un sans séjour (« pour_qui »). Chaque service devient une ligne que la cuisine " \
                          "accepte ou refuse. Un EMAIL PART AU RESPONSABLE de chaque prestation (jamais au client). " \
                          "Les repas d'un séjour peuvent aussi passer par modifier_sejour.",
             schema: {
               properties: {
                 sejour: SEJOUR,
                 pour_qui: { type: "string", description: "Sans séjour : pour qui est la demande (« École de Spontin »)." },
                 origine: { type: "string", enum: MealOrder::ORIGINS,
                            description: "reception (saisie de l'accueil, défaut) ou client (demandé par le client)." },
                 prestations: { type: "array", items: PRESTATION_A_COMMANDER, minItems: 1 }
               },
               required: %w[prestations]
             }

        def self.transactionnel? = false

        private

        def planifier(arguments)
          stay = arguments["sejour"].present? ? sejour!(arguments["sejour"]) : nil
          pour_qui = arguments["pour_qui"].to_s.strip.presence
          raise Error, "Donne un séjour, ou pour qui est la demande (pour_qui)." if stay.nil? && pour_qui.nil?

          pour_qui = nil if stay
          origine = arguments["origine"].presence || "reception"
          raise Error, "origine : client ou reception." unless MealOrder::ORIGINS.include?(origine)

          blocs = Array(arguments["prestations"]).each_with_index.flat_map { |p, i| blocs_de(p, i, origine) }
          lignes = blocs.flat_map { |bloc| lignes_apercu(bloc, stay, pour_qui) }
          doublons!(lignes, stay, pour_qui)

          resume = ["#{lignes.size} service(s) pour #{stay ? "le séjour ##{stay.id} (#{nom_sejour(stay)})" : "« #{pour_qui} » (sans séjour)"} :"]
          lignes.each do |order|
            resume << "- #{quand(order)} · #{order.label} · #{order.people} pers. · #{order.status_label} · " \
                      "#{responsable_apercu(order)} · #{euros(order.unit_price_effective_cents * order.people)}" \
                      "#{" · ⚠ #{order.warnings.join(' ; ')}" if order.warnings.any?}"
          end
          resume << emails(lignes)
          resume << "Remise formule trio éventuelle appliquée à l'enregistrement." if lignes.any? { |o| o.family == "repas" }
          resume << "Le total du séjour sera recalculé." if stay

          Plan.new(resume: resume.join("\n"),
                   empreinte: [stay && etat(stay), pour_qui, arguments_signes(arguments)],
                   donnees: { stay_id: stay&.id, pour_qui: pour_qui, blocs: blocs })
        end

        def appliquer(plan)
          stay = plan.donnees[:stay_id] && Stay.find(plan.donnees[:stay_id])
          blocs = plan.donnees[:blocs].map do |bloc|
            Kitchen::GridSubmission::Block.new(index: bloc[:index], attributes: bloc[:attributes], cells: bloc[:cells])
          end
          resultat = Kitchen::GridSubmission.new(stay: stay, contact_label: plan.donnees[:pour_qui], blocks: blocs).run
          raise Error, "Rien n'a été créé : #{resultat.error}" unless resultat.success?

          recalculer!(stay)
          commandes = MealOrder.includes(:responsible_human, stay: :customer).where(id: resultat.orders.map(&:id)).order(:date, :id)
          "#{commandes.size} prestation(s) créée(s) :\n#{commandes.map { |o| "- #{ligne_prestation(o)}" }.join("\n")}"
        end

        # Une prestation donne un bloc de grille pour ses services avec moment,
        # et un bloc par service sans moment (la grille ne sait pas les cocher).
        def blocs_de(prestation, index, origine)
          kind = type!(prestation["type"])
          attributs = { kind: kind, people: convives!(prestation["convives"]), origin: origine,
                        status: prestation["statut"].presence || "requested", notes: prestation["precisions"].presence }
          raise Error, "statut : #{MealOrder::STATUSES.join(', ')}." unless MealOrder::STATUSES.include?(attributs[:status])
          raise Error, "Une nouvelle demande ne peut pas être déjà annulée." if attributs[:status] == "cancelled"

          prix = prix_unitaire(prestation["prix_par_personne"])
          attributs[:unit_price_cents] = prix if prix.is_a?(Integer)
          if prestation["responsable"].present?
            attributs[:responsible_human_id] = membre!(prestation["responsable"]).id
            # Se charger d'un buffet ou d'un apéro vaut acceptation ; les repas
            # gardent la validation de Stéphanie (OrdersController#apply_kitchen_acceptance).
            attributs.merge!(validation: "accepted", validated_at: Time.current) unless MealOrder::KIND_FAMILIES[kind] == "repas"
          end
          attributs.compact!

          services = Array(prestation["services"]).map do |service|
            moment = moment!(service["moment"])
            raise Error, "Le goûter ne se commande qu'avec le type repas." if moment == "gouter" && kind != "repas"

            [date!(service["date"], "date"), moment]
          end
          raise Error, "Prestation #{index + 1} : donne au moins un service (date et moment)." if services.empty?

          avec, sans = services.partition { |_, moment| moment }
          blocs = []
          if avec.any?
            cellules = avec.each_with_object({}) { |(date, moment), h| (h[date.iso8601] ||= {})[moment] = "1" }
            blocs << { index: index, attributes: attributs, cells: cellules }
          end
          sans.each { |date, _| blocs << { index: index, attributes: attributs.merge(date: date.iso8601), cells: {} } }
          blocs
        end

        # Les lignes telles que la grille les créera, pour l'aperçu.
        def lignes_apercu(bloc, stay, pour_qui)
          services = if bloc[:cells].any?
                       bloc[:cells].flat_map { |jour, moments| moments.keys.map { |m| [Date.iso8601(jour), m] } }
                     else
                       [[Date.iso8601(bloc[:attributes][:date]), nil]]
                     end
          services.sort_by { |date, m| [date, Kitchen::GridSubmission::MOMENTS.index(m).to_i] }.map do |date, moment|
            kind = moment == "gouter" && bloc[:attributes][:kind] == "repas" ? "gouter" : bloc[:attributes][:kind]
            order = MealOrder.new(bloc[:attributes].except(:date).merge(kind: kind, date: date, moment: moment,
                                                                         stay: stay, contact_label: pour_qui))
            order.responsible_human ||= Kitchen::Config.default_human(order.family)
            raise Error, "#{quand(order)} : #{order.errors.full_messages.to_sentence}" unless order.valid?

            order
          end
        end

        # Rejouer la même commande ne la double pas : une ligne identique et
        # active créée dans l'heure arrête tout.
        def doublons!(lignes, stay, pour_qui)
          recentes = MealOrder.active.where(created_at: 1.hour.ago..)
          recentes = stay ? recentes.where(stay_id: stay.id) : recentes.where(stay_id: nil, contact_label: pour_qui)
          lignes.each do |order|
            deja = recentes.find_by(kind: order.kind, date: order.date, moment: order.moment, people: order.people)
            next unless deja

            raise Error, "Déjà commandé il y a moins d'une heure : prestation ##{deja.id} (#{quand(deja)}, #{deja.label}). " \
                         "Rien n'a été créé ; modifie-la plutôt (modifier_prestation)."
          end
        end

        def responsable_apercu(order)
          nom = order.responsible_human&.name || "personne"
          etat = order.accepted? ? "accepté" : "à valider par la cuisine"
          "#{nom} (#{etat})"
        end

        def emails(lignes)
          futures = lignes.reject(&:past?)
          destinataires = futures.filter_map { |o| destinataire_cuisine(o) }.uniq
          return "Aucun email (services passés ou sans responsable)." if destinataires.empty?

          "Email à : #{destinataires.join(', ')} (jamais au client)."
        end
      end
    end
  end
end
