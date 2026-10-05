module Mcp
  module Tools
    module Cuisine
      # Ce que partagent les outils de la cuisine : retrouver une prestation
      # (une ligne MealOrder = un service), un membre, et décrire la ligne.
      #
      # La page Cuisine est fermée aux porteurs d'activité restreints
      # (`BaseController::RESTRICTED_ALLOWLIST`) : ces outils aussi.
      module Commun
        PRESTATION = {
          type: %w[integer string],
          description: "Identifiant de la prestation (#123), rendu par prestations_cuisine ou fiche_sejour (« Repas #123 »)."
        }.freeze

        TYPE = {
          type: "string",
          description: "repas (midi ou soir, Stéphanie), buffet_vege, buffet_viande ou apero. Le goûter se commande " \
                       "avec le type repas et le moment gouter."
        }.freeze

        MOMENT = { type: "string", enum: MealOrder::MOMENTS, description: "midi, gouter ou soir." }.freeze

        STATUT = {
          type: "string", enum: MealOrder::STATUSES,
          description: "Statut côté client : inquiry (demande d'info), requested (demande ferme), confirmed, cancelled."
        }.freeze

        MEMBRE = {
          type: "string",
          description: "Membre de l'équipe (nom ou partie du nom, ex. « Stéphanie »), ou « moi » pour le compte connecté."
        }.freeze

        FAMILLE = { type: "string", enum: MealOrder::FAMILIES, description: "repas, buffet ou apero." }.freeze

        # La garde passe AVANT l'outil, aperçu compris : un porteur restreint
        # n'atteint pas la page Cuisine dans Claudy, il ne l'atteint pas ici.
        module Garde
          def call(arguments)
            if user.restricted_to_own_activities?
              raise Base::Error, "La cuisine n'est pas accessible à un compte de porteur d'activité, comme dans Claudy."
            end

            super
          end
        end

        def self.included(base)
          base.prepend(Garde)
        end

        private

        def prestation!(reference)
          id = reference.to_s.delete("#").strip
          raise Base::Error, "Précise la prestation (identifiant #123)." unless id.match?(/\A\d+\z/)

          MealOrder.includes(:responsible_human, stay: :customer).find_by(id: id) ||
            raise(Base::Error, "Aucune prestation ##{id} (ou elle a été supprimée).")
        end

        # Un membre ACTIF (le défaut de `Human`), comme le menu « Confier à ».
        def membre!(reference)
          reference = reference.to_s.strip
          raise Base::Error, "Précise le membre (nom, ou « moi »)." if reference.empty?

          if reference.casecmp?("moi")
            return user.human || raise(Base::Error, "Ton compte n'est rattaché à aucun membre : donne un nom.")
          end

          humains = Human.where("name ILIKE ?", "%#{Human.sanitize_sql_like(reference)}%").order(:name).to_a
          exact = humains.find { |h| h.name.casecmp?(reference) }
          return exact if exact
          return humains.first if humains.one?
          raise Base::Error, "Aucun membre actif ne s'appelle « #{reference} »." if humains.empty?

          raise Base::Error, "Plusieurs membres correspondent à « #{reference} » : #{humains.map(&:name).join(', ')}."
        end

        # Les types proposés à la saisie, comme la grille : sans trio ni goûter
        # (ils se cochent), et sans les familles retirées de l'offre.
        def type!(valeur, actuel: nil)
          cle = valeur.to_s.strip.downcase
          permis = Kitchen::Config.enabled_kinds
          permis |= [actuel] if actuel
          return cle if permis.include?(cle)

          retire = MealOrder::KINDS.include?(cle) && !Kitchen::Config::UNPROPOSABLE_KINDS.include?(cle)
          raise Base::Error, "Le type « #{valeur} » est retiré de l'offre (Paramètres > Cuisine)." if retire

          raise Base::Error, "Type inconnu : « #{valeur} ». Types proposés : #{permis.join(', ')} " \
                             "(goûter : type repas, moment gouter)."
        end

        def moment!(valeur)
          return nil if valeur.blank?
          return valeur if MealOrder::MOMENTS.include?(valeur)

          raise Base::Error, "Moment inconnu : « #{valeur} » (midi, gouter ou soir)."
        end

        def convives!(valeur)
          nombre = Integer(valeur.to_s, exception: false)
          raise Base::Error, "convives : un nombre entier de personnes, au moins 1." unless nombre&.positive?

          nombre
        end

        # Prix par personne en euros. `nil` : pas d'override, le barème joue.
        # « aucun » efface un prix imposé (`:effacer`).
        def prix_unitaire(valeur)
          return nil if valeur.nil?
          return :effacer if valeur.to_s.strip.match?(/\A(|aucun|non|bareme|barème|null)\z/i)

          texte = valeur.to_s.strip.delete(" €").tr(",", ".")
          raise Base::Error, "prix_par_personne : montant illisible « #{valeur} »." unless texte.match?(/\A\d+(\.\d{1,2})?\z/)

          (BigDecimal(texte) * 100).to_i
        end

        def quand(order)
          return "sans date" if order.date.blank?

          "#{I18n.l(order.date, format: '%a %d/%m/%Y')}#{" #{order.moment_label.downcase}" if order.moment.present?}"
        end

        # Une ligne par prestation : de quoi la reconnaître et la désigner.
        def ligne_prestation(order)
          pour = order.stay_id ? "#{order.client_label} (séjour ##{order.stay_id})" : "#{order.client_label} (sans séjour)"
          responsable = order.responsible_human&.name || "personne ne s'en charge"
          details = ["Prestation ##{order.id} #{quand(order)}", order.label, "#{order.people} pers.", pour,
                     order.status_label, "cuisine : #{order.validation_label.downcase}", responsable,
                     "#{euros(order.price_cents)}#{' (non facturé)' unless order.billable?}"]
          details << "refus : #{order.refusal_reason}" if order.refused? && order.refusal_reason.present?
          details << "annulation : #{order.cancellation_reason}" if order.cancelled? && order.cancellation_reason.present?
          details.join(" · ")
        end

        def avertissements(order)
          order.warnings.map { |w| "⚠ #{w}." }
        end

        # Le total du séjour suit chaque mouvement de cuisine (la page Cuisine ne
        # le recalcule pas : la fiche séjour le ferait à la modification suivante).
        def recalculer!(stay)
          return unless stay

          stay.reload.recompute_aggregates!
          stay.set_payment_status
        end

        # Qui reçoit l'email interne que déclenchera l'écriture (jamais le client).
        def destinataire_cuisine(order)
          Kitchen::Notifier.responsible_email_for(order).presence
        end

        def etat_prestation(order)
          [order.id, order.updated_at&.utc&.iso8601(6)]
        end
      end
    end
  end
end
