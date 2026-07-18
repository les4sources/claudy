class StaysController < BaseController
  before_action :set_accounting_view, only: :show
  before_action :set_stay, only: %i[edit update destroy]

  # Rendu sans layout : le fragment HTML est injecté dans la modale de détails
  # par le contrôleur Stimulus stay-details (fetch + innerHTML). [tranche 1]
  def show
    @stay = Stay.includes(stay_items: :bookable, customer: []).find(params[:id]).decorate
    # Créneaux proposables à l'ajout d'activité (epic #55, Phase 6), bornés au
    # périmètre de l'utilisateur (admin global : tout ; porteur : ses activités).
    @assignable_availabilities = ExperienceAvailability.for_user(current_user)
                                                       .upcoming
                                                       .includes(:experience)
    render layout: false
  end

  # Vue admin Pôle Accueil — Stays récents filtrables par canal d'attribution
  # (source), pour observer la transition Tally → /reservation (AC-T2-23/24).
  # Protégée Devise via BaseController (préserve ISC-3).
  def recent
    @source = params[:source].presence
    @sources = Stay::SOURCES
    @stays = Stay.from_source(@source).recent.includes(:customer).limit(100).decorate
  end

  # --- CRUD Séjour admin (epic #66, Phase 1) --------------------------------
  # Le séjour devient le point d'entrée de création composable côté admin
  # (hébergement + activités), en réutilisant `Reservations::Builder` en mode
  # admin (aucun Stripe, aucun email forcé, force-dispo, statut au choix).

  def new
    @stay  = Stay.new(status: "pending")
    @draft = Reservations::Draft.new
    prepare_form
  end

  def create
    @draft  = build_draft
    builder = Reservations::Builder.new(
      draft:             @draft,
      admin:             true,
      status:            requested_status,
      source:            "manual",
      skip_availability: force_availability?
    )

    if builder.run
      flash[:notice] = "Séjour créé."
      flash[:alert]  = builder.availability_warning if builder.availability_warning
      redirect_to recent_stays_path
    else
      @stay  = Stay.new(status: requested_status.presence || "pending")
      @quote = safe_quote(@draft)
      flash.now[:alert] = builder.error_message(default: "Le séjour n'a pas pu être créé.")
      prepare_form
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    @draft = draft_from_stay(@stay)
    prepare_form
  end

  def update
    @draft  = build_draft
    updater = Stays::AdminUpdater.new(
      stay:              @stay,
      draft:             @draft,
      status:            requested_status,
      skip_availability: force_availability?,
      user:              current_user
    )

    if updater.run
      flash[:notice] = "Séjour mis à jour."
      flash[:alert]  = updater.availability_warning if updater.availability_warning
      redirect_to recent_stays_path
    else
      @quote = safe_quote(@draft)
      flash.now[:alert] = updater.error_message(default: "Le séjour n'a pas pu être mis à jour.")
      prepare_form
      render :edit, status: :unprocessable_entity
    end
  end

  # Suppression = soft-delete (soft_deletion + PaperTrail), jamais de hard destroy.
  def destroy
    @stay.soft_delete!(validate: false)
    redirect_to recent_stays_path, notice: "Séjour supprimé."
  end

  private

  def set_stay
    @stay = Stay.find(params[:id])
  end

  def set_accounting_view
    @accounting_view = true
  end

  # Données partagées par les vues new/edit.
  def prepare_form
    @lodgings  = bookable_lodgings
    @customers = Customer.order(:organization_name, :last_name, :first_name).limit(1_000)
    @assignable_availabilities = ExperienceAvailability.for_user(current_user)
                                                       .upcoming
                                                       .includes(:experience)
    @statuses = Stay::STATUSES_ADMIN_CREATABLE
    @quote  ||= safe_quote(@draft)
  end

  # Hébergements tarifables (barème B2C forfaitaire, `Pricing::Catalog`), dans
  # l'ordre du catalogue. Même barème que le funnel public — surtout PAS le
  # barème admin par tier (décision figée epic #66).
  def bookable_lodgings
    names = Pricing::Catalog::LODGING_RATES.keys
    Lodging.where(name: names).sort_by { |l| names.index(l.name) || 99 }
  end

  # Construit un `Reservations::Draft` (contrat commun Builder/PricingModel)
  # depuis les paramètres du formulaire admin.
  def build_draft
    p = stay_params
    contact = customer_contact(p)
    Reservations::Draft.new(
      lodging_id:     p[:lodging_id],
      arrival_date:   p[:arrival_date],
      departure_date: p[:departure_date],
      adults:         p[:adults],
      children:       p[:children],
      dogs_count:     p[:dogs_count],
      group_name:     p[:group_name],
      first_name:     contact[:first_name],
      last_name:      contact[:last_name],
      email:          contact[:email],
      phone:          contact[:phone],
      experiences:    activity_entries(p),
      halls:          space_entries(p)
    )
  end

  # Reconstruit un draft depuis un séjour existant, pour préremplir le form edit.
  def draft_from_stay(stay)
    booking = stay.stay_items.where(bookable_type: "Booking").first&.bookable
    Reservations::Draft.new(
      lodging_id:     booking&.lodging_id,
      arrival_date:   stay.arrival_date,
      departure_date: stay.departure_date,
      adults:         booking&.adults,
      children:       booking&.children,
      group_name:     booking&.group_name,
      first_name:     stay.customer&.first_name,
      last_name:      stay.customer&.last_name,
      email:          stay.customer&.email,
      phone:          stay.customer&.phone,
      experiences:    stay.experience_bookings.active.map { |eb|
        { id: eb.experience&.id, availability_id: eb.experience_availability_id, participants: eb.participants }
      },
      halls:          halls_from_stay(stay)
    )
  end

  # Reconstruit les lignes d'espaces {kind, date, period} d'un séjour depuis son
  # SpaceBooking (réservations existantes), pour préremplir le form edit. Le nom
  # de la Space est re-mappé vers sa clé de pricing (grande_salle, …).
  def halls_from_stay(stay)
    space_booking = stay.stay_items.where(bookable_type: "SpaceBooking").first&.bookable
    return [] if space_booking.nil?

    space_booking.space_reservations.map do |res|
      key = space_key_for_name(res.space&.name)
      next if key.nil?
      { kind: key, date: res.date&.iso8601, period: res.duration }
    end.compact
  end

  # Space#name → clé de pricing (inverse de SpaceComposition::SPACE_NAMES_BY_KEY).
  def space_key_for_name(name)
    return nil if name.blank?
    SpaceComposition::SPACE_NAMES_BY_KEY.find { |_key, names| names.include?(name) }&.first
  end

  # Coordonnées client : soit un client existant sélectionné (on lit ses
  # coordonnées pour que le Builder/Updater le retrouve par email), soit un
  # nouveau client saisi à la volée.
  def customer_contact(p)
    if p[:customer_mode].to_s == "new"
      nc = p[:new_customer] || {}
      { first_name: nc[:first_name], last_name: nc[:last_name], email: nc[:email], phone: nc[:phone] }
    elsif (customer = Customer.find_by(id: p[:customer_id]))
      { first_name: customer.first_name, last_name: customer.last_name, email: customer.email, phone: customer.phone }
    else
      {}
    end
  end

  # Entrées d'activités : chaque ligne porte un créneau (`availability_id`) et un
  # nombre de participants. On borne au périmètre de l'utilisateur et on résout
  # l'`experience_id` (nécessaire au devis B2C via `PricingModel`).
  def activity_entries(p)
    rows = p[:experiences]
    rows = rows.respond_to?(:values) ? rows.values : Array(rows)
    allowed = ExperienceAvailability.for_user(current_user).index_by(&:id)

    rows.filter_map do |row|
      availability_id = row[:availability_id].to_i
      participants    = row[:participants].to_i
      next if availability_id < 1 || participants < 1
      avail = allowed[availability_id]
      next unless avail
      { id: avail.experience_id, availability_id: availability_id, participants: participants }
    end
  end

  # Entrées d'espaces (epic #66, Phase 2) : chaque ligne du form porte un espace
  # (`kind` = clé de pricing grande_salle/petite_salle/cuisine_pro), une `date` et
  # une `period` (journee/soiree/journee_et_soiree). On écarte les lignes
  # incomplètes ; le résultat alimente `Reservations::Draft#halls` — commun au
  # devis (PricingModel) ET à la persistance (SpaceComposition).
  def space_entries(p)
    rows = p[:halls]
    rows = rows.respond_to?(:values) ? rows.values : Array(rows)
    rows.filter_map do |row|
      kind   = row[:kind].to_s
      date   = row[:date].to_s
      period = row[:period].to_s
      next if kind.blank? || date.blank? || period.blank?
      { kind: kind, date: date, period: period }
    end
  end

  def requested_status
    stay_params[:status]
  end

  def force_availability?
    ActiveModel::Type::Boolean.new.cast(stay_params[:force_availability])
  end

  def safe_quote(draft)
    draft&.quote
  rescue StandardError
    nil
  end

  def stay_params
    params.fetch(:stay, {})
  end

  def set_presenters; end
end
