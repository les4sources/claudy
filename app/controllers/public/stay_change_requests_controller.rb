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
      # Heures d'arrivée/départ portées par le SÉJOUR (refonte 2026-07-22) :
      # reportées depuis l'état courant pour qu'une demande approuvée ne les
      # efface pas (le formulaire de modification client ne les affiche pas).
      attrs[:arrival_time]   = current.arrival_time
      attrs[:departure_time] = current.departure_time
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
      @stay_days            = stay_days
      # La grille ESPACES lit `space_slots` ; le séjour reconstruit, lui, rend
      # des lignes `halls`. Sans cette conversion, le client ouvrait « modifier
      # mon séjour » sur une grille VIDE — et sa demande, une fois approuvée,
      # retirait ses salles sans un mot (epic #234, phase 3). Même service que
      # le formulaire admin : un seul préremplissage pour les deux écrans.
      Stays::SpaceGridPrefill.apply!(@draft, @stay_days)
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
      @baseline_quote_cents ||= begin
        current = Stays::DraftReconstructor.call(@stay)
        # MÊME représentation des espaces des deux côtés du delta : le
        # formulaire soumet une grille `space_slots`, la référence doit donc en
        # être une aussi. Sans cela, un formulaire intact affichait un delta —
        # les lignes `halls` et la grille ne se tarifent pas pareil depuis les
        # forfaits multi-jours (epic #234, phase 2).
        # Fenêtre du séjour ACTUEL, pas celle du formulaire : si le client
        # déplace ses dates, la référence reste ce qu'il a réservé.
        Stays::SpaceGridPrefill.apply!(current, days_of(current))
        current.quote.total_excluding_experiences_cents
      end
    end

    # Jours [arrivée, départ] d'un draft quelconque — départ inclus, comme la
    # grille Espaces.
    def days_of(draft)
      return [] if draft.arrival_date.blank? || draft.departure_date.blank?
      return [] if draft.departure_date < draft.arrival_date

      (draft.arrival_date..draft.departure_date).to_a
    end

    def stay_nights
      return [] if @draft.arrival_date.blank? || @draft.departure_date.blank?

      (@draft.arrival_date...@draft.departure_date).to_a
    end

    # Jours de la grille ESPACES, départ INCLUS (epic #234, Phase 1) : la
    # modification client rend le MÊME partial que le funnel et l'admin — ce qui
    # est corrigé d'un côté l'est des trois.
    def stay_days
      days_of(@draft)
    end

    def bookable_lodgings
      names = ["La Hulotte", "La Chevêche", "Le Grand-Duc"]
      Lodging.where(name: names).sort_by { |l| names.index(l.name) || 99 }
    end

    # Grille de dispo affichée dans le calendrier d'hébergement : la propre
    # occupation du séjour ne doit PAS s'y compter comme indisponible.
    # Statuts bloquants (Michael 2026-09-08) : `Stay::BLOCKING_STATUSES`.
    def build_stay_availability(lodgings, nights)
      return {} if nights.empty?

      own_ids = @stay.stay_items.where(bookable_type: "Booking").pluck(:bookable_id)

      lodgings.each_with_object({}) do |lodging, result|
        room_ids = lodging.rooms.pluck(:id)
        scope = Reservation.includes(:booking)
                           .where(date: nights.first..nights.last, room: room_ids,
                                  booking: { status: Stay::BLOCKING_STATUSES })
        scope = scope.where.not(booking: { id: own_ids }) if own_ids.any?
        occupied = scope.pluck(:date).to_set |
                   lodging.unavailabilities.where(date: nights.first..nights.last).pluck(:date).to_set
        result[lodging.id] = nights.map { |night| !occupied.include?(night) }
      end
    end
  end
end
