class StaysController < BaseController
  before_action :set_accounting_view, only: :show
  before_action :set_stay, only: %i[edit update destroy update_status]

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
      flash[:alert]  = combined_warning(builder)
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
      flash[:alert]  = combined_warning(updater)
      redirect_to recent_stays_path
    else
      @quote = safe_quote(@draft)
      flash.now[:alert] = updater.error_message(default: "Le séjour n'a pas pu être mis à jour.")
      prepare_form
      render :edit, status: :unprocessable_entity
    end
  end

  # Disponibilité de l'hébergement en temps réel (issue #77). Réutilise
  # `Lodging#available_between?` (source unique de vérité, veto Grand-Duc /
  # chambres partagées inclus). Répond en JSON, INFORME sans bloquer : le form
  # garde la checkbox « Forcer la disponibilité » comme seule décision de blocage.
  #   - `checkable: false` tant que l'hébergement ou les dates manquent ;
  #   - `available: true/false` sinon.
  def availability
    lodging = Lodging.find_by(id: params[:lodging_id])
    from    = parse_form_date(params[:arrival_date])
    to      = parse_form_date(params[:departure_date])

    if lodging.nil? || from.nil? || to.nil? || to < from
      return render json: { checkable: false }
    end

    render json: {
      checkable: true,
      available: lodging.available_between?(from, to),
      lodging:   lodging.name
    }
  end

  # Devis live du form de composition (issue #73). Reconstruit le `Draft` depuis
  # les params du form (même helper que create/update) et recalcule le panneau
  # « Devis (B2C) » via `PricingModel` — MÊME barème que le submit, aucun nouveau
  # calcul. Réponse Turbo Stream qui remplace le panneau sur place.
  def quote
    @draft = build_draft
    @quote = safe_quote(@draft)

    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace("stay-quote-panel", partial: "stays/quote_panel")
      end
    end
  end

  # Action rapide depuis la modale du calendrier (issue #76) : bascule pending ↔
  # confirmed sans ouvrir le form d'édition. Propage le statut aux réservables
  # pour garder le veto de dispo cohérent (cf. `Stays::QuickStatusUpdater`).
  # Réponse Turbo Stream : rafraîchit le contenu de la modale sur place.
  def update_status
    updater = Stays::QuickStatusUpdater.new(stay: @stay, status: params[:status])
    ok = updater.run
    @stay = Stay.includes(stay_items: :bookable, customer: []).find(@stay.id).decorate
    @assignable_availabilities = ExperienceAvailability.for_user(current_user).upcoming.includes(:experience)

    respond_to do |format|
      format.turbo_stream do
        flash.now[:alert] = updater.error_message unless ok
        render turbo_stream: turbo_stream.replace("stay-details-#{@stay.id}", partial: "stays/details")
      end
      format.html { redirect_to recent_stays_path, notice: (ok ? "Statut mis à jour." : updater.error_message) }
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

  # Concatène l'avertissement de disponibilité (force-dispo) et celui des espaces
  # non enregistrables (issue #75), pour un flash unique. nil si aucun des deux.
  def combined_warning(service)
    [service.availability_warning, service.space_warning].compact.join(" ").presence
  end

  def set_accounting_view
    @accounting_view = true
  end

  # Données partagées par les vues new/edit.
  def prepare_form
    @lodgings  = bookable_lodgings
    # Client existant : autocomplete via `customers/search` (issue #74). On ne
    # précharge plus TOUS les clients — seul le client courant (édition) alimente
    # le `<select>` de repli sans-JS. La recherche dynamique fait le reste.
    @customers = Customer.where(id: @stay&.customer_id).to_a
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
      halls:          space_entries(p),
      campings:       camping_entries(p),
      vans:           van_entries(p),
      meals:          meal_entries(p)
    )
  end

  # Nombre de nuits déduit des dates du formulaire (pour tarifer camping/van).
  def nights_from_params(p)
    arrival   = parse_form_date(p[:arrival_date])
    departure = parse_form_date(p[:departure_date])
    return 0 if arrival.nil? || departure.nil?
    (departure - arrival).to_i.clamp(0, 10_000)
  end

  def parse_form_date(value)
    return nil if value.blank?
    Date.parse(value.to_s)
  rescue ArgumentError, TypeError
    nil
  end

  # Camping (epic #66, Phase 3) : le form porte un nombre de personnes ; le
  # camping occupe toute la fenêtre du séjour (nights déduit des dates).
  def camping_entries(p)
    people = p.dig(:camping, :people).to_i
    return [] if people < 1
    nights = nights_from_params(p)
    return [] if nights < 1
    [{ kind: "tente", people: people, nights: nights }]
  end

  # Van / camping-car : le form porte un nombre de véhicules. Une entrée par
  # véhicule (contrat PricingModel : une ligne `:van` par entrée).
  def van_entries(p)
    vehicles = p.dig(:van, :vehicles).to_i
    return [] if vehicles < 1
    nights = nights_from_params(p)
    return [] if nights < 1
    Array.new(vehicles) { { nights: nights } }
  end

  # Repas datés {kind, date, people} — on écarte les lignes incomplètes.
  def meal_entries(p)
    rows = p[:meals]
    rows = rows.respond_to?(:values) ? rows.values : Array(rows)
    rows.filter_map do |row|
      kind   = row[:kind].to_s
      people = row[:people].to_i
      next if kind.blank? || people < 1
      { kind: kind, date: row[:date].to_s.presence, people: people }
    end
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
      halls:          halls_from_stay(stay),
      campings:       campings_from_stay(stay),
      vans:           vans_from_stay(stay),
      meals:          meals_from_stay(stay)
    )
  end

  # Reconstruit l'entrée camping {kind, people, nights} depuis le CampingBooking
  # persisté, pour préremplir le form edit (nights déduit de la fenêtre).
  def campings_from_stay(stay)
    camping = stay.stay_items.where(bookable_type: "CampingBooking").first&.bookable
    return [] if camping.nil?
    nights = camping.from_date && camping.to_date ? (camping.to_date - camping.from_date).to_i : stay.experience_bookings.size
    [{ kind: camping.kind, people: camping.people, nights: [nights, 1].max }]
  end

  # Reconstruit les entrées van (une par véhicule) depuis le VanBooking persisté.
  def vans_from_stay(stay)
    van = stay.stay_items.where(bookable_type: "VanBooking").first&.bookable
    return [] if van.nil?
    nights = van.from_date && van.to_date ? (van.to_date - van.from_date).to_i : 1
    Array.new([van.vehicles, 1].max) { { nights: [nights, 1].max } }
  end

  # Reconstruit les repas {kind, date, people} depuis les MealOrder du séjour.
  def meals_from_stay(stay)
    stay.meal_orders.map do |order|
      { kind: order.kind, date: order.date&.iso8601, people: order.people }
    end
  end

  # Reconstruit les lignes d'espaces {kind, date, period} d'un séjour depuis son
  # SpaceBooking (réservations existantes), pour préremplir le form edit. Le nom
  # de la Space est re-mappé vers sa clé de pricing (grande_salle, …).
  def halls_from_stay(stay)
    space_booking = stay.stay_items.where(bookable_type: "SpaceBooking").first&.bookable
    return [] if space_booking.nil?

    space_booking.space_reservations.map do |res|
      key = space_key_for(res.space)
      next if key.nil?
      { kind: key, date: res.date&.iso8601, period: res.duration }
    end.compact
  end

  # `Space` → clé de pricing (inverse du mapping SpaceComposition). Résolution par
  # le `code` stable d'abord (issue #75), puis repli sur le nom d'affichage.
  def space_key_for(space)
    return nil if space.nil?

    by_code = SpaceComposition::SPACE_CODES_BY_KEY.find { |_key, code| code == space.code }&.first
    return by_code if by_code

    SpaceComposition::SPACE_NAMES_BY_KEY.find { |_key, names| names.include?(space.name) }&.first
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
