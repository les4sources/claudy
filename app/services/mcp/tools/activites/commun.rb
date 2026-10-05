module Mcp
  module Tools
    module Activites
      # Ce que partagent les outils des activités. Tout passe par les mêmes
      # périmètres que l'interface : un porteur restreint (`restricted_to_experiences`)
      # ne voit et ne touche que SES activités, comme dans Claudy.
      module Commun
        ACTIVITE = { type: %w[integer string], description: "Activité : identifiant (#12) ou partie de son nom (« ânes »)." }.freeze
        CRENEAU = { type: %w[integer string], description: "Identifiant du créneau (#345), rendu par fiche_activite ou disponibilites." }.freeze
        RESERVATION = {
          type: %w[integer string],
          description: "Identifiant de la réservation d'activité (#678), rendu par reservations_activites ou fiche_sejour."
        }.freeze

        private

        def activites
          scope = Experience.includes(:human)
          user.restricted_to_own_activities? ? scope.where(human_id: user.human_id.presence || 0) : scope
        end

        def activite!(reference)
          reference = reference.to_s.strip.delete_prefix("#")
          raise Base::Error, "Précise l'activité (identifiant ou nom)." if reference.empty?
          return activites.find_by(id: reference) || raise(Base::Error, "Aucune activité ##{reference}.") if reference.match?(/\A\d+\z/)

          trouvees = activites.where("experiences.name ILIKE ?", "%#{Experience.sanitize_sql_like(reference)}%").to_a
          exacte = trouvees.find { |a| a.name.casecmp?(reference) }
          return exacte if exacte
          return trouvees.first if trouvees.one?
          raise Base::Error, "Aucune activité ne correspond à « #{reference} »." if trouvees.empty?

          raise Base::Error, "Plusieurs activités correspondent à « #{reference} » : " \
                             "#{trouvees.map { |a| "##{a.id} #{a.name}" }.join(', ')}."
        end

        def creneau!(reference)
          id = reference.to_s.delete("#").strip
          ExperienceAvailability.for_user(user).includes(:experience).find_by(id: id) ||
            raise(Base::Error, "Créneau ##{id} introuvable (ou hors de ton périmètre).")
        end

        def reservation!(reference)
          id = reference.to_s.delete("#").strip
          ExperienceBooking.for_user(user).includes(:stay, experience_availability: :experience).find_by(id: id) ||
            raise(Base::Error, "Réservation d'activité ##{id} introuvable (ou hors de ton périmètre).")
        end

        # Les gestes que l'interface réserve à l'équipe (créer une activité,
        # ajouter une activité à un séjour, déclarer en lot…).
        def equipe!
          return unless user.restricted_to_own_activities?

          raise Base::Error, "Ce geste est réservé à l'équipe : un porteur d'activité ne peut pas le faire."
        end

        def porteur!(reference)
          reference = reference.to_s.strip
          return nil if reference.empty?

          humains = Human.where("name ILIKE ?", "%#{Human.sanitize_sql_like(reference)}%").to_a
          exact = humains.find { |h| h.name.casecmp?(reference) }
          return exact if exact
          return humains.first if humains.one?
          raise Base::Error, "Personne ne s'appelle « #{reference} » parmi les membres actifs." if humains.empty?

          raise Base::Error, "Plusieurs membres correspondent à « #{reference} » : #{humains.map(&:name).join(', ')}."
        end

        def ligne_creneau(creneau)
          places = creneau.available_spots
          reste = if places.nil? then "sans limite" elsif places.zero? then "complet" else "#{places} place(s) libre(s)" end
          "Créneau ##{creneau.id} #{creneau.experience&.name} le #{creneau.available_on} à #{creneau.starts_at} " \
            "(#{creneau.effective_duration} min) : #{creneau.booked_participants} inscrit(s), #{reste}"
        end

        def ligne_reservation(resa)
          creneau = resa.experience_availability
          sejour = resa.stay
          client = sejour&.customer&.name
          tenue = resa.outcome_recorded? ? " · #{resa.outcome_label}" : ""
          "Réservation ##{resa.id} #{creneau&.experience&.name} le #{creneau&.available_on} à #{creneau&.starts_at} · " \
            "#{resa.participants} pers. · #{resa.status_label}#{tenue} · #{euros(resa.price_cents)} · " \
            "séjour ##{resa.stay_id}#{" (#{client})" if client}#{" · refus : #{resa.refusal_reason}" if resa.refused?}"
        end

        # Le total du séjour suit chaque mouvement d'activité, comme dans l'écran.
        def recalculer!(stay)
          stay.recompute_aggregates!
          stay.set_payment_status
        end

        def email_client_activite(resa)
          email = resa.stay&.customer&.email
          return nil if email.blank? || resa.stay.customer.catch_all?

          email
        end
      end
    end
  end
end
