module Kitchen
  # Page Cuisine (epic #219, phase 3) — le tableau de Malau, dans Claudy.
  #
  # L'onglet « Repas de Steph » qu'elle tenait à la main groupait les lignes par
  # client, avec un total, en sections « Demandes / Confirmé à venir / Archives /
  # Annulés ». On reprend cette forme, rattachée aux séjours et à l'historique.
  class OrdersController < BaseController
    breadcrumb "Cuisine", :kitchen_orders_path, match: :exact

    before_action :set_order, only: [:edit, :update, :status, :assign, :accept, :new_refusal, :refuse, :shopping_list]

    # Sections de l'index, dans l'ordre de lecture. Une ligne tombe dans la
    # PREMIÈRE qui la reçoit : une demande d'info en attente de validation est un
    # travail à faire, pas une ligne à lire deux fois.
    SECTIONS = [
      # Issue #238 : EN TÊTE, avant tout le reste. Un service refusé dont la date
      # approche est le seul travail vraiment urgent de la page — il faut prévoir
      # autre chose. Claudy le signale ; il ne crée aucun buffet de remplacement
      # à la place de Michael (décision 6).
      { key: :to_cover,  title: "À couvrir",
        blurb: "La cuisine s'est désistée et la date approche — il faut prévoir autre chose." },
      { key: :todo,      title: "À traiter",
        blurb: "La cuisine n'a pas encore répondu." },
      { key: :upcoming,  title: "À venir",
        blurb: "Acceptées par la cuisine, à servir." },
      { key: :inquiries, title: "Demandes d'info",
        blurb: "Le client se renseigne, rien n'est engagé." },
      { key: :archives,  title: "Archives",
        blurb: "Déjà passées." },
      { key: :cancelled, title: "Annulés et refusés",
        blurb: "Retirées du jeu, gardées pour mémoire." }
    ].freeze

    ARCHIVE_LIMIT   = 100
    CANCELLED_LIMIT = 50
    RECENT_ARCHIVE_MONTHS = 12

    def index
      @families    = Kitchen::Config.families
      @responsible = responsible_filter
      @family      = family_filter
      @old_archives = params[:old_archives] == "1"
      @responsible_options = responsible_options
      @humans   = Human.where(status: "active").order(:name)
      @sections = build_sections
    end

    def new
      @order = MealOrder.new(new_order_defaults)
      prepare_form
    end

    def create
      @order = MealOrder.new(order_params.merge(stay_id: params.dig(:meal_order, :stay_id)))
      accept_when_someone_takes_it(@order)

      return create_from_grid if grid_submission?

      if @order.save
        redirect_to kitchen_orders_path, notice: "Demande enregistrée."
      else
        prepare_form
        flash.now[:alert] = @order.errors.full_messages.to_sentence
        render :new, status: :unprocessable_entity
      end
    end

    # Autocomplete JSON du champ « Séjour ». Un sélecteur natif de 300 entrées
    # triées par date d'arrivée est illisible : on cherche sur ce qu'on a sous la
    # main quand le client est au téléphone — son nom, le nom du groupe porté par
    # sa réservation, son email, son numéro.
    def stay_search
      stays = Stays::Search.new(assignable_stays, params[:q]).call
      stays = stays.none if params[:q].to_s.strip.length < Stays::Search::MIN_LENGTH

      render json: stays.limit(10).map { |stay| stay_search_result(stay) }
    end

    def edit
      prepare_form
    end

    def update
      was_accepted = @order.accepted?

      if @order.update(order_params)
        redirect_to kitchen_orders_path, notice: update_notice(was_accepted)
      else
        prepare_form
        flash.now[:alert] = @order.errors.full_messages.to_sentence
        render :edit, status: :unprocessable_entity
      end
    end

    # Statut CLIENT depuis la ligne : ferme, confirmé, annulé (motif obligatoire).
    def status
      attrs = { status: params[:status] }
      attrs[:cancellation_reason] = params[:cancellation_reason] if params[:status] == "cancelled"

      if params[:status] == "cancelled" && params[:cancellation_reason].blank?
        redirect_to kitchen_orders_path, alert: "Un motif est nécessaire pour annuler une demande."
      elsif @order.update(attrs)
        redirect_to kitchen_orders_path, notice: "Statut mis à jour."
      else
        redirect_to kitchen_orders_path, alert: @order.errors.full_messages.to_sentence
      end
    end

    # « Je m'en charge » / « Réassigner ». Pour un buffet ou un apéro, se charger
    # d'une demande VAUT validation : il n'y a personne d'autre à attendre.
    #
    # La personne est TOUJOURS nommée : les postes sont partagés sous un compte
    # commun, et retomber sur `current_user` désignerait le poste, pas la
    # personne devant l'écran.
    def assign
      human = Human.find_by(id: params[:human_id])

      if human.nil?
        redirect_to kitchen_orders_path, alert: "Choisissez qui s'en charge."
        return
      end

      @order.responsible_human = human
      accept_when_someone_takes_it(@order)

      if @order.save
        redirect_to kitchen_orders_path, notice: "#{human.name} s'en charge."
      else
        redirect_to kitchen_orders_path, alert: @order.errors.full_messages.to_sentence
      end
    end

    # Canal ADMIN de la validation (phase 4), en miroir du canal jeton. Les
    # comptes sont partagés : n'importe quel utilisateur connecté répond, sans
    # filtrage par personne (décision Michael).
    def accept
      @order.accept!
      redirect_back fallback_location: kitchen_orders_path, notice: "C'est noté comme possible."
    end

    def new_refusal
      prepare_form
    end

    def refuse
      @order.refuse!(params.dig(:meal_order, :refusal_reason))
      redirect_to kitchen_orders_path, notice: "Refus enregistré. L'accueil est prévenu."
    rescue ActiveRecord::RecordInvalid
      flash.now[:alert] = "Un motif est nécessaire pour refuser."
      prepare_form
      render :new_refusal, status: :unprocessable_entity
    end

    # Liste de courses imprimable (epic #219, phase 6). Le gabarit `print`
    # n'affiche aucune navigation — inutile de la masquer nous-mêmes.
    def shopping_list
      @shopping_list = Kitchen::ShoppingList.new(@order)
      render layout: "print"
    end

    private

    def set_order
      @order = MealOrder.find(params[:id])
    end

    def order_params
      params.require(:meal_order).permit(:kind, :moment, :date, :people, :notes, :status,
                                         :cancellation_reason, :responsible_human_id,
                                         :cost_notes)
            .merge(unit_price_cents: submitted_unit_price_cents,
                   cost_cents: submitted_cost_cents)
            .compact
    end

    # Prix unitaire saisi en euros, virgule tolérée. Vide = on retombe sur le
    # tarif (donc `nil`, pas zéro).
    def submitted_unit_price_cents
      raw = params.dig(:meal_order, :unit_price)
      return nil if raw.nil?
      return "" if raw.to_s.strip.blank? # `compact` ne l'enlève pas : on veut bien effacer l'override

      (raw.to_s.tr(",", ".").to_f * 100).round
    end

    def submitted_cost_cents
      raw = params.dig(:meal_order, :cost)
      return nil if raw.nil?
      return "" if raw.to_s.strip.blank?

      (raw.to_s.tr(",", ".").to_f * 100).round
    end

    # Ni type ni responsable préremplis. Le type l'était par le premier type
    # activé, et le responsable par le défaut de CE type : basculer le type sans
    # toucher au responsable laissait un buffet au nom de Stéphanie — et, comme
    # `accept_when_someone_takes_it` voit un responsable nommé, ACCEPTÉ par la
    # cuisine sans que personne ne l'ait accepté. Le type se coche donc
    # explicitement, et `MealOrder#assign_default_responsible` affecte le
    # responsable à partir de la famille réellement choisie.
    def new_order_defaults
      { stay_id: params[:stay_id].presence, people: 1, status: "requested" }
    end

    # Se charger d'un buffet ou d'un apéro vaut acceptation (décision Michael) —
    # la famille `repas` garde sa validation par Stéphanie, elle seule cuisine.
    def accept_when_someone_takes_it(order)
      return if order.responsible_human_id.blank?
      return if order.family == "repas"
      return if order.refused? || order.accepted?

      order.validation   = "accepted"
      order.validated_at = Time.current
    end

    def update_notice(was_accepted)
      return "Demande mise à jour." unless was_accepted && @order.pending?

      "Demande mise à jour. La prestation a changé : la cuisine doit revalider."
    end

    # La grille (issue #238) : une soumission par CASES, pas par ligne unique.
    # Elle n'existe que pour un séjour aux dates connues — sans calendrier, il
    # n'y a pas de colonnes, et le formulaire retombe sur date + moment.
    def grid_submission?
      params[:grid_mode] == "1"
    end

    def create_from_grid
      result = Kitchen::GridSubmission.new(
        stay: @order.stay,
        attributes: grid_line_attributes,
        cells: params[:grid]
      ).run

      if result.success?
        redirect_to kitchen_orders_path,
                    notice: "#{result.orders.size} service(s) enregistré(s)."
      else
        prepare_form
        flash.now[:alert] = result.error
        render :new, status: :unprocessable_entity
      end
    end

    # Ce qui se saisit UNE FOIS et s'applique à toutes les lignes créées.
    def grid_line_attributes
      @order.attributes
            .slice("kind", "people", "notes", "status", "unit_price_cents",
                   "responsible_human_id", "validation", "validated_at")
            .symbolize_keys
    end

    def prepare_form
      @stays  = assignable_stays
      @humans = Human.where(status: "active").order(:name)
      @kinds  = MealOrder::KIND_LABELS.filter_map do |kind, label|
        [label, kind] if Kitchen::Config.enabled_kinds.include?(kind) || kind == @order.kind
      end
      @grid_days = grid_days_for(@order)
    end

    # Les jours de la grille : du jour d'arrivée au jour de départ INCLUS — le
    # départ porte un midi. Vide quand le séjour n'a pas ses deux dates : le
    # formulaire retombe alors sur un champ Date et un champ Moment uniques.
    def grid_days_for(order)
      stay = order.stay
      return [] if stay.blank? || stay.arrival_date.blank? || stay.departure_date.blank?
      return [] if stay.departure_date < stay.arrival_date

      (stay.arrival_date..stay.departure_date).to_a
    end

    # Les séjours qu'on peut encore garnir : pas annulés, pas partis depuis plus
    # d'un mois. Au-delà, la liste devient illisible pour rien.
    def assignable_stays
      Stay.includes(:customer)
          .where.not(status: %w[canceled declined])
          .where("departure_date >= ? OR departure_date IS NULL", Date.current - 30)
          .order(Arel.sql("arrival_date ASC NULLS LAST"))
          .limit(300)
    end

    # Ce que la liste de résultats affiche : le nom d'abord, puis de quoi
    # distinguer deux séjours du même client fidèle — les dates — et de quoi
    # confirmer qu'on tient le bon dossier — le groupe et le contact.
    def stay_search_result(stay)
      customer = stay.customer
      { id: stay.id,
        label: helpers.stay_choice_label(stay),
        group: customer&.organization_name.presence,
        contact: [customer&.email, customer&.phone].compact_blank.join(" · ") }
    end

    def base_scope
      scope = MealOrder.includes(:responsible_human, stay: :customer)
      scope = scope.of_family(@family) if @family.present?
      scope = scope.where(responsible_human_id: @responsible) if @responsible.present?
      scope
    end

    def family_filter
      value = params[:family].to_s
      MealOrder::FAMILIES.include?(value) ? value : nil
    end

    def responsible_filter
      value = params[:responsible_human_id].to_s
      value.presence && (Human.exists?(id: value) ? value : nil)
    end

    def responsible_options
      Human.where(id: MealOrder.distinct.pluck(:responsible_human_id).compact).order(:name)
    end

    def build_sections
      # « À couvrir » se sert la première : une ligne refusée mais encore à venir
      # ne doit plus se lire dans « Annulés et refusés », où elle passerait pour
      # une affaire classée.
      to_cover  = base_scope.to_cover.chronological.to_a
      claimed   = to_cover.map(&:id)

      todo      = base_scope.pending_validation.upcoming.chronological.to_a
                            .reject { |o| claimed.include?(o.id) }
      claimed  += todo.map(&:id)

      upcoming  = base_scope.where(validation: "accepted", status: %w[requested confirmed])
                            .upcoming.chronological.to_a.reject { |o| claimed.include?(o.id) }
      claimed  += upcoming.map(&:id)

      inquiries = base_scope.where(status: "inquiry").upcoming.chronological.to_a
                            .reject { |o| claimed.include?(o.id) }
      claimed  += inquiries.map(&:id)

      archives  = archive_scope.antichronological.limit(ARCHIVE_LIMIT).to_a
                               .reject { |o| claimed.include?(o.id) }
      claimed  += archives.map(&:id)

      cancelled = base_scope.where(status: "cancelled").or(base_scope.where(validation: "refused"))
                            .antichronological.limit(CANCELLED_LIMIT).to_a
                            .reject { |o| claimed.include?(o.id) }

      rows = { to_cover: to_cover, todo: todo, upcoming: upcoming, inquiries: inquiries,
               archives: archives, cancelled: cancelled }

      SECTIONS.map { |section| section.merge(groups: group_by_stay(rows.fetch(section[:key]))) }
    end

    def archive_scope
      scope = base_scope.past.where.not(status: "cancelled")
      return scope if @old_archives

      scope.where("date >= ?", RECENT_ARCHIVE_MONTHS.months.ago.to_date)
    end

    # Groupé par séjour, comme le tableau de Malau : un en-tête par client, et le
    # sous-total de ce qui compte vraiment (les lignes facturables).
    def group_by_stay(orders)
      orders.group_by(&:stay).map do |stay, lines|
        { stay: stay&.decorate,
          orders: MealOrderDecorator.decorate_collection(lines),
          subtotal_cents: lines.select(&:billable?).sum { |o| o.price_cents.to_i } }
      end
    end

    def set_presenters
      @home_view = true
    end
  end
end
