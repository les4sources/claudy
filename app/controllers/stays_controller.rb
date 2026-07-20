class StaysController < BaseController
  before_action :set_accounting_view, only: :show
  before_action :set_stay, only: %i[edit update destroy update_status]

  # Index admin des séjours (epic #81) — le séjour devient le point d'entrée
  # unique. Tableau paginé (30/page) orienté GESTION des réservations et
  # paiements : contact, canal, dates + statut, composition compacte, et surtout
  # total / encaissé / reste dû exigible + statut de paiement.
  #
  # Filtres légers : « Tous » (défaut), « À venir » (current_and_future),
  # « Passés » (past). Les montants agrégés (encaissé, reste dû) sont calculés
  # EN LOT par `Stays::IndexAmounts` (aucun N+1 — voir le service).
  def index
    @filter = params[:filter].presence_in(%w[upcoming past]) # nil = tous
    @stays  = index_scope
              .includes(
                :customer,
                :meal_orders,
                { stay_items: :bookable },
                { experience_bookings: { experience_availability: :experience } }
              )
              .paginate(page: params[:page], per_page: 30)

    # Agrégats monétaires de la page (encaissé + reste dû exigible) — calculés
    # AVANT décoration, sur les enregistrements préchargés, en une requête de
    # paiements pour toute la page.
    @amounts = Stays::IndexAmounts.new(@stays).call
    @stays   = StayDecorator.decorate_collection(@stays)
  end

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

  # Saisie rapide datée + duplication (epic #81, Phase 7). Le form NEW se
  # préremplit selon les params :
  #   - `duplicate_from` → reprise du séjour source (client + composition, sans
  #     dates ni paiement ni prix imposé), via `Stays::DuplicateService` ;
  #   - `date`           → arrivée = date, départ = date + 1 (1 nuit, hébergement) ;
  #   - `date` + `space` → une ligne d'espace datée, SANS dates de séjour (journée
  #     sèche : composition d'espace légitime).
  def new
    @stay  = Stay.new(status: "pending")
    @draft = build_prefilled_draft
    prepare_form
  end

  def create
    @draft  = build_draft
    builder = Reservations::Builder.new(
      draft:                @draft,
      admin:                true,
      status:               requested_status,
      source:               requested_source || "manual",
      platform:             requested_platform,
      price_override_cents: requested_price_override_cents,
      skip_availability:    force_availability?
    )

    if builder.run
      # Notes admin appliquées APRÈS la création : la note interne saisie est
      # CONCATÉNÉE avec l'éventuelle note auto du Builder (avertissement
      # multi-chiens) — on ne l'écrase jamais. La note publique est posée telle quelle.
      apply_admin_notes(builder.stay, merge_auto: true)
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
    @draft = Stays::DraftReconstructor.new(@stay).to_draft
    prepare_form
  end

  def update
    @draft  = build_draft
    updater = Stays::AdminUpdater.new(
      stay:                 @stay,
      draft:                @draft,
      status:               requested_status,
      source:               requested_source,
      platform:             requested_platform,
      price_override_cents: requested_price_override_cents,
      skip_availability:    force_availability?,
      user:                 current_user
    )

    if updater.run
      # À l'édition, le form préremplit les notes courantes : simple écrasement
      # (note interne texte brut + note publique ActionText), pas de concaténation.
      apply_admin_notes(@stay, merge_auto: false)
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

    # Mode chambres seules (epic #81, Phase 5) : la dispo porte sur les chambres
    # cochées, pas sur tout le gîte. Sans chambre cochée, rien à vérifier.
    if params[:booking_type].to_s == "rooms"
      room_ids = Array(params[:room_ids]).reject(&:blank?)
      return render json: { checkable: false } if room_ids.empty?
      return render json: {
        checkable: true,
        available: lodging.rooms_available_between?(room_ids, from, to),
        lodging:   lodging.name
      }
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
  # Déléguée à `Stays::DestroyService` : le soft-delete du Stay ne cascade PAS sur
  # ses bookables (Booking/SpaceBooking/Camping/Van) — le service les soft-delete
  # explicitement pour qu'AUCUNE occupation (chambres, espaces) ne survive au
  # calendrier ni au veto de dispo (issue #99). Les paiements sont conservés.
  def destroy
    Stays::DestroyService.new(stay: @stay).run
    redirect_to recent_stays_path, notice: "Séjour supprimé."
  end

  # --- Fusion de séjours depuis le calendrier (epic #81, Phase 2) -----------
  # Trois fragments SERVEUR successifs. Aucune vérité n'est recalculée en JS :
  # l'étape A (désignation) comme l'étape B (aperçu) sortent d'ici.

  # Étape A — cartes radio de désignation du survivant, avec présélection
  # intelligente motivée. Reçoit `stay_ids[]` (+ éventuel `target_id` pour
  # re-cocher la cible au retour depuis l'aperçu).
  def merge_setup
    @stays = load_merge_stays
    return render_merge_guard if @stays.size < 2

    preselected = @stays.find { |s| s.id == params[:target_id].to_i }
    suggested, reason = helpers.suggested_merge_target(@stays)
    @target = preselected || suggested
    @suggested_id = suggested&.id
    @suggested_reason = reason

    render partial: "stays/merge_setup",
           layout: false,
           formats: [:html],
           locals: { stays: @stays, target: @target, suggested_id: @suggested_id, suggested_reason: @suggested_reason }
  end

  # Étape B — aperçu dry-run (Stays::MergePreview). Reçoit `target_id` + `stay_ids[]`.
  def merge_preview
    stays = load_merge_stays
    return render_merge_guard if stays.size < 2

    target = resolve_merge_target(stays)
    return render_merge_guard(message: "Le séjour survivant ne fait pas partie de la sélection.") if target.nil?
    sources = stays.reject { |s| s.id == target.id }

    preview = Stays::MergePreview.new(target: target, sources: sources).call
    render partial: "stays/merge_preview", layout: false, formats: [:html], locals: { preview: preview, error: nil }
  end

  # Commit — Stays::MergeService, puis redirection calendrier (mois du début du
  # survivant) + flash détaillé. En cas d'échec, re-rendu du fragment d'aperçu
  # avec l'erreur DANS le dialog (422). Appelé en fetch JSON par le contrôleur
  # Stimulus (le flash persiste jusqu'au GET de redirection qui l'affiche).
  def merge
    stays = load_merge_stays
    return render_merge_guard if stays.size < 2

    target = resolve_merge_target(stays)
    return render_merge_guard(message: "Le séjour survivant ne fait pas partie de la sélection.") if target.nil?
    sources = stays.reject { |s| s.id == target.id }

    service = Stays::MergeService.new(target: target, sources: sources)
    if service.run
      target.reload
      flash[:notice] = merge_success_message(target, sources)
      render json: {
        redirect: root_path(date: target.arrival_date&.strftime("%Y-%m-%d"), stay_merge_done: 1)
      }
    else
      preview = Stays::MergePreview.new(target: target, sources: sources).call
      render partial: "stays/merge_preview",
             layout: false,
             formats: [:html],
             status: :unprocessable_entity,
             locals: { preview: preview, error: service.error_message }
    end
  end

  private

  # Relation de base de l'index selon le filtre actif. « À venir » / « Passés »
  # réutilisent les scopes du modèle (qui portent DÉJÀ leur propre tri utile :
  # arrivée asc pour l'à-venir, arrivée desc pour le passé). « Tous » (défaut) :
  # arrivée la plus récente/future d'abord — les séjours sans date d'arrivée
  # (activités/repas seuls) rejetés en fin de liste, tri stable sur l'id.
  def index_scope
    case @filter
    when "upcoming" then Stay.current_and_future
    when "past"     then Stay.past
    else Stay.order(Arel.sql("arrival_date DESC NULLS LAST, id DESC"))
    end
  end

  # Draft de préremplissage du form NEW (epic #81, Phase 7). Trois cas, dans
  # l'ordre de priorité : duplication d'un séjour, saisie datée d'un espace,
  # saisie datée d'un hébergement. À défaut, un draft vierge.
  def build_prefilled_draft
    if (source = duplicate_source)
      # Le client du séjour source est PRÉSÉLECTIONNÉ dans le <select> « Client
      # existant » (sinon le prérempli n'atterrissait que dans les champs masqués
      # du panneau « Nouveau client » et une soumission partait sans customer_id).
      @preselected_customer_id = source.customer_id
      return Stays::DuplicateService.call(stay: source)
    end

    date = parse_form_date(params[:date])
    return Reservations::Draft.new if date.nil?

    if params[:space].present?
      # Espace en journée sèche : une ligne d'espace datée, aucune date de séjour.
      Reservations::Draft.new(halls: [{ date: date.iso8601 }])
    else
      # Hébergement : arrivée = date, départ = lendemain (1 nuit par défaut).
      Reservations::Draft.new(arrival_date: date.iso8601, departure_date: (date + 1).iso8601)
    end
  end

  # Séjour source d'une duplication (`duplicate_from`). nil si absent ou introuvable.
  def duplicate_source
    id = params[:duplicate_from]
    return nil if id.blank?
    Stay.find_by(id: id)
  end

  # Séjours candidats à la fusion, préchargés pour éviter les N+1 des aperçus.
  def load_merge_stays
    ids = Array(params[:stay_ids]).map(&:to_i).uniq.reject(&:zero?)
    stays = Stay.where(id: ids)
                .includes(:customer, :meal_orders, experience_bookings: { experience_availability: :experience }, stay_items: :bookable)
                .to_a
    preload_public_notes(stays)
    stays
  end

  # `public_notes` est de l'ActionText (`has_rich_text`) porté par Booking et
  # SpaceBooking UNIQUEMENT. Le `bookable` étant polymorphe (types mixtes —
  # Camping/Van n'ont pas de rich text), on ne peut pas l'`includes` dans la
  # requête ci-dessus sans lever une erreur ; on précharge donc le rich text sur
  # le seul sous-ensemble concerné, pour que la carte de désignation puisse tester
  # la présence d'une note publique sans N+1.
  def preload_public_notes(stays)
    notable = stays.flat_map(&:stay_items)
                   .map(&:bookable)
                   .select { |b| b.is_a?(Booking) || b.is_a?(SpaceBooking) }
    return if notable.empty?

    ActiveRecord::Associations::Preloader.new(
      records: notable, associations: :rich_text_public_notes
    ).call
  end

  # Résout le survivant STRICTEMENT parmi les séjours postés : un `target_id`
  # forgé hors sélection ne doit jamais retomber silencieusement sur un autre
  # séjour (le survivant serait choisi à l'insu de l'admin). Sans `target_id`
  # (ouverture de l'étape B sans passer par A), repli déterministe : plus petit id.
  def resolve_merge_target(stays)
    return stays.min_by(&:id) if params[:target_id].blank?

    stays.find { |s| s.id == params[:target_id].to_i }
  end

  # Garde-fou serveur : moins de 2 séjours résolus = fusion impossible (422).
  def render_merge_guard(message: "Sélectionne au moins deux séjours existants à fusionner.")
    render partial: "stays/merge_error",
           layout: false,
           formats: [:html],
           status: :unprocessable_entity,
           locals: { message: message }
  end

  def merge_success_message(target, sources)
    ids = sources.map { |s| "##{s.id}" }.join(" et ")
    total = helpers.humanized_money_with_symbol(target.total_amount)
    balance = helpers.humanized_money_with_symbol(Money.new(target.amount_due_cents))
    "Séjour#{'s' if sources.size > 1} #{ids} fusionné#{'s' if sources.size > 1} dans ##{target.id} — total recalculé : #{total}, solde : #{balance}."
  end

  def set_stay
    @stay = Stay.find(params[:id])
  end

  # Applique la note interne (colonne `notes`, texte brut) et la note publique
  # (`public_notes`, ActionText) saisies au form. `merge_auto` distingue les deux
  # canaux : à la CRÉATION, on concatène la note interne saisie avec l'éventuelle
  # note auto déjà posée par le Builder (multi-chiens) ; à l'ÉDITION, on écrase.
  def apply_admin_notes(stay, merge_auto:)
    return if stay.nil?

    admin_internal = stay_params[:notes].to_s.strip.presence
    stay.notes =
      if merge_auto
        [admin_internal, stay.notes.to_s.strip.presence].compact.uniq.join("\n\n").presence
      else
        admin_internal
      end

    stay.public_notes = stay_params[:public_notes] if stay_params.key?(:public_notes)
    stay.save!
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
    @customers = Customer.where(id: [@stay&.customer_id, @preselected_customer_id].compact).to_a
    @assignable_availabilities = ExperienceAvailability.for_user(current_user)
                                                       .upcoming
                                                       .includes(:experience)
    @statuses = Stay::STATUSES_ADMIN_CREATABLE
    # Événements sélectionnables pour la facturation espace (epic #81, Phase 6),
    # décorés pour l'affichage « nom (dates) » — même source que le form direct.
    @events = EventDecorator.decorate_collection(Event.order(starts_at: :desc))
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
      booking_type:   p[:booking_type],
      room_ids:       room_ids_param(p),
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
      meals:          meal_entries(p),
      # Facturation espace (epic #81, Phase 6) : le sous-hash brut transite tel
      # quel ; le Draft normalise (presence → nil) et la persistance convertit les
      # montants via les setters `monetize`. Absent du form → `space_billing` nil,
      # les valeurs existantes survivent à la réédition.
      space_billing:  p[:space_billing]
    )
  end

  # Chambres cochées (mode chambres seules, epic #81, Phase 5). Tableau de la
  # forme stay[room_ids][] ; on ne garde que des entiers exploitables.
  def room_ids_param(p)
    Array(p[:room_ids]).map { |id| id.to_i }.reject(&:zero?)
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

  # Canal d'attribution du séjour (epic #81, Phase 3). Validé contre `SOURCES`
  # (le service borne / préserve ensuite). nil si absent ou forgé — l'appelant
  # décide du repli (create → "manual" ; update → source d'origine préservée).
  def requested_source
    src = stay_params[:source]
    Stay::SOURCES.include?(src) ? src : nil
  end

  # Attribution OTA à propager au Booking d'occupation (Airbnb/Booking.com/web).
  def requested_platform
    stay_params[:platform].presence
  end

  # Prix imposé (€ saisis) → cents. Vide = nil (pas d'override → devis B2C).
  # Tolère la virgule décimale (locale FR) et un éventuel symbole/espaces.
  def requested_price_override_cents
    raw = stay_params[:price_override].to_s.strip
    return nil if raw.blank?
    normalized = raw.tr(",", ".").delete("^0-9.-")
    return nil if normalized.blank?
    cents = (BigDecimal(normalized) * 100).round
    # Négatif = saisie invalide, jamais un prix (le `min: 0` du champ n'est
    # qu'un garde-fou client). 0 € reste un override valide.
    cents.negative? ? nil : cents
  rescue ArgumentError
    nil
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
