module Public
  # Demande de modification d'un séjour par le client (issue #133).
  #
  # Canal jeton, comme la page `/sejour/:token` : pas de Devise. Le client
  # recompose son séjour dans un formulaire prérempli, voit le nouveau total et
  # le delta en direct, et SOUMET UNE DEMANDE — le séjour n'est jamais modifié
  # ici. C'est l'équipe qui approuve ou refuse.
  class StayChangeRequestsController < Public::BaseController
    layout "public_sheet"

    before_action :load_stay
    before_action :ensure_modifiable

    # Formulaire de composition prérempli depuis le séjour.
    def new
      @draft = Stays::DraftReconstructor.call(@stay)
      prepare_form
    end

    # Devis live : nouveau total + delta, en Turbo Stream.
    def quote
      @draft = draft_from_params
      prepare_form
      respond_to do |format|
        format.turbo_stream { render :quote }
        format.html { redirect_to new_public_stay_change_request_path(@stay.token) }
      end
    end

    def create
      @draft = draft_from_params
      prepare_form

      # Disponibilité vérifiée À LA SOUMISSION (informative) — et re-vérifiée à
      # la validation par l'équipe, parce que le monde bouge entre les deux.
      unless Stays::LodgingAvailability.call(stay: @stay, draft: @draft)
        flash.now[:alert] = t("public.stay_change_requests.unavailable")
        return render :new, status: :unprocessable_entity
      end

      change_request = build_change_request

      # « La nouvelle remplace l'ancienne » : on retire les demandes en attente
      # précédentes, puis on enregistre. Si l'enregistrement échoue (IBAN
      # manquant, par exemple), le ROLLBACK rend son ancienne demande au client
      # — on ne détruit jamais quelque chose pour rien.
      saved = ActiveRecord::Base.transaction do
        supersede_previous_pending
        raise ActiveRecord::Rollback unless change_request.save

        true
      end

      if saved
        StayChangeRequestMailer.team_new_request(change_request).deliver_later
        StayChangeRequestMailer.customer_received(change_request).deliver_later

        redirect_to public_stay_path(@stay.token),
                    notice: t("public.stay_change_requests.submitted")
      else
        @change_request = change_request
        flash.now[:alert] = change_request.errors.full_messages.to_sentence
        render :new, status: :unprocessable_entity
      end
    end

    private

    def load_stay
      @stay = Stay.find_by!(token: params[:token]).decorate
    rescue ActiveRecord::RecordNotFound
      raise ActionController::RoutingError, "Not Found"
    end

    # Un séjour déjà parti (départ < aujourd'hui) ne se modifie plus. La page
    # `/sejour/:token` n'affiche d'ailleurs pas le bouton dans ce cas.
    def ensure_modifiable
      return if @stay.departure_date.present? && @stay.departure_date >= Date.current

      redirect_to public_stay_path(@stay.token),
                  alert: t("public.stay_change_requests.too_late")
    end

    # Le formulaire du client ne porte QUE ce qu'il peut recomposer :
    # hébergement nuit par nuit, camping/van/hamacs et espaces — exactement les
    # grilles du funnel public, réutilisées telles quelles (donc préfixe
    # `reservation[...]`, comme elles l'émettent).
    #
    # Tout le reste est REPORTÉ depuis le séjour actuel : activités (hors
    # périmètre v1 — elles gardent leur flux propre), repas, terrasse,
    # facturation espace et coordonnées client. Sans ce report, une demande
    # approuvée effacerait silencieusement ce que le formulaire n'affiche pas.
    def draft_from_params
      current = Stays::DraftReconstructor.call(@stay)
      attrs = submitted_draft_params

      attrs[:experiences]   = current.experiences
      attrs[:meals]         = current.meals
      attrs[:terrasses]     = current.terrasses
      attrs[:space_billing] = current.space_billing
      attrs[:first_name]    = current.first_name
      attrs[:last_name]     = current.last_name
      attrs[:email]         = current.email
      attrs[:phone]         = current.phone
      attrs[:group_name]    = attrs[:group_name].presence || current.group_name

      Reservations::Draft.new(attrs)
    end

    def submitted_draft_params
      params.fetch(:reservation, {}).permit(
        :lodging_id, :arrival_date, :departure_date, :dogs_count,
        :adults, :children, :group_name,
        lodging_night_ids: [],
        per_night_resources: { tente: [], van: [], hamac_simple: [], hamac_double: [] },
        space_slots: { grande_salle: [], petite_salle: [], cuisine_pro: [] }
      ).to_h.symbolize_keys
    end

    def build_change_request
      StayChangeRequest.new(
        stay: @stay.object,
        draft_snapshot: @draft.to_h,
        new_total_cents: @new_total_cents,
        delta_cents: @delta_cents,
        refund_iban: params[:refund_iban]
      )
    end

    def supersede_previous_pending
      StayChangeRequest.pending
                       .where(stay_id: @stay.id)
                       .find_each { |old| old.soft_delete!(validate: false) }
    end

    # Ivars attendues par les partiels de composition réutilisés du funnel.
    def prepare_form
      @lodgings             = bookable_lodgings
      @stay_nights          = stay_nights
      @lodging_availability = build_stay_availability(@lodgings, @stay_nights)
      @quote                = @draft.quote
      # PRIX PRÉSERVÉ (décision 2026-07-21) : beaucoup de séjours portent un
      # prix historique/négocié/OTA différent du barème actuel. On ne recote
      # donc JAMAIS le séjour entier — le delta est la différence entre la
      # recote de la composition PROPOSÉE et la recote de la composition
      # ACTUELLE (même barème des deux côtés), appliquée au prix existant.
      # Formulaire intact → delta 0 ; une nuit ajoutée → + son prix catalogue.
      @delta_cents          = @quote.total_excluding_experiences_cents - baseline_quote_cents
      @new_total_cents      = @stay.total_amount_cents.to_i + @delta_cents
      @refund_cents         = [@stay.amount_paid_cents.to_i - @new_total_cents, 0].max
    end

    # Recote de la composition ACTUELLE du séjour, au barème du jour — le point
    # de référence du delta.
    def baseline_quote_cents
      @baseline_quote_cents ||=
        Stays::DraftReconstructor.call(@stay).quote.total_excluding_experiences_cents
    end

    def stay_nights
      return [] if @draft.arrival_date.blank? || @draft.departure_date.blank?

      (@draft.arrival_date...@draft.departure_date).to_a
    end

    def bookable_lodgings
      names = ["La Hulotte", "La Chevêche", "Le Grand-Duc"]
      Lodging.where(name: names).sort_by { |l| names.index(l.name) || 99 }
    end

    # Grille de dispo affichée dans le calendrier d'hébergement : la propre
    # occupation du séjour ne doit PAS s'y compter comme indisponible.
    def build_stay_availability(lodgings, nights)
      return {} if nights.empty?

      own_ids = @stay.stay_items.where(bookable_type: "Booking").pluck(:bookable_id)

      lodgings.each_with_object({}) do |lodging, result|
        room_ids = lodging.rooms.pluck(:id)
        scope = Reservation.includes(:booking)
                           .where(date: nights.first..nights.last, room: room_ids,
                                  booking: { status: "confirmed" })
        scope = scope.where.not(booking: { id: own_ids }) if own_ids.any?
        occupied = scope.pluck(:date).to_set |
                   lodging.unavailabilities.where(date: nights.first..nights.last).pluck(:date).to_set
        result[lodging.id] = nights.map { |night| !occupied.include?(night) }
      end
    end
  end
end
