module Kitchen
  # Page Cuisine (epic #219, phase 3) — le tableau de Malau, dans Claudy.
  #
  # L'onglet « Repas de Steph » qu'elle tenait à la main groupait les lignes par
  # client, avec un total, en sections « Demandes / Confirmé à venir / Archives /
  # Annulés ». On reprend cette forme, rattachée aux séjours et à l'historique.
  class OrdersController < BaseController
    breadcrumb "Cuisine", :kitchen_orders_path, match: :exact

    before_action :set_order,
                  only: [:edit, :update, :destroy, :status, :assign, :accept, :new_refusal, :refuse,
                         :shopping_list, :attach]

    # DEUX VUES (2026-10-19), au lieu de sept onglets qui se recoupaient : une
    # même demande apparaissait dans trois onglets à la fois, et ni Stéphanie
    # ni Malau ne savaient lequel ouvrir. Chaque vue montre TOUTES les demandes
    # à venir, une seule fois, rangées par statut (`MealOrder#board_status`) ;
    # ce qui change d'une vue à l'autre, c'est l'ordre des sections et les
    # gestes proposés. La vue choisie est retenue (cookie) : les postes sont
    # partagés, c'est donc l'appareil qui s'en souvient, pas le compte.
    VIEWS = [
      { key: :kitchen,   title: "Cuisine" },
      { key: :reception, title: "Accueil" }
    ].freeze
    # Hors du jeu, en pied de page : le passé et les annulés.
    ARCHIVE_VIEWS = [
      { key: :past, title: "Passé, 12 derniers mois" },
      { key: :out,  title: "Annulés" }
    ].freeze
    WORKING_VIEW_KEYS = VIEWS.map { |v| v[:key] }.freeze
    VIEW_KEYS = (VIEWS + ARCHIVE_VIEWS).map { |v| v[:key] }.freeze
    VIEW_COOKIE = :kitchen_view

    # L'ordre des sections : d'abord ce que CE métier doit faire.
    SECTIONS = {
      kitchen:   %w[to_validate planned inquiry to_cover],
      reception: %w[to_cover inquiry to_validate planned]
    }.freeze

    # Ce qui fait l'état de la page (vue, filtres) : la suppression le renvoie
    # pour qu'on retombe là où l'on était.
    INDEX_PARAMS = %i[view family origin responsible_human_id old_archives].freeze

    ARCHIVE_LIMIT   = 100
    CANCELLED_LIMIT = 50
    RECENT_ARCHIVE_MONTHS = 12

    def index
      @view         = view_param
      remember_view
      @origin       = origin_filter
      @family       = family_filter
      @responsible  = responsible_filter
      @old_archives = params[:old_archives] == "1"
      @humans       = Human.where(status: "active").order(:name)
      # Le menu d'une demande orpheline propose de la rattacher (issue #315) :
      # il lui faut la même liste de séjours que le formulaire de création.
      @stays        = assignable_stays
      @counts       = view_counts
      # Les montants n'intéressent que le Pôle Accueil : ils ne s'affichent que
      # dans sa vue.
      @show_money   = @view == :reception

      if working_view?
        grouped   = decorated_live_rows.group_by(&:board_status)
        @sections = SECTIONS[@view].map { |status| [status, grouped[status] || []] }
        @total_cents = (grouped["planned"] || []).select(&:billable?).sum { |o| o.price_cents.to_i }
      else
        @rows = MealOrderDecorator.decorate_collection(rows_for(@view))
      end
    end

    def new
      @order = MealOrder.new(new_order_defaults)
      prepare_form
    end

    def create
      return create_prestations if params[:prestations].present?

      @order = MealOrder.new(order_params.merge(stay_id: params.dig(:meal_order, :stay_id).presence))
      accept_when_someone_takes_it(@order)

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

    # Rattacher une demande orpheline à un séjour, une fois celui-ci créé
    # (issue #315). Sens unique : on ne détache pas, et on ne déplace pas d'un
    # séjour à l'autre — déplacer une demande, c'est en créer une.
    #
    # `contact_label` est CONSERVÉ : c'est ce que Malau avait noté au premier
    # contact, et il peut différer du nom du client finalement enregistré.
    def attach
      stay = Stay.find_by(id: params[:stay_id].presence)

      if stay.nil?
        redirect_back fallback_location: kitchen_orders_path, alert: "Choisissez un séjour."
      elsif @order.stay_id.present?
        redirect_back fallback_location: kitchen_orders_path,
                      alert: "Cette demande est déjà rattachée à un séjour."
      elsif @order.attach_to_stay!(stay)
        redirect_back fallback_location: kitchen_orders_path,
                      notice: "Demande rattachée au séjour de #{stay.customer&.name.presence || "##{stay.id}"}."
      else
        redirect_back fallback_location: kitchen_orders_path,
                      alert: @order.errors.full_messages.to_sentence
      end
    rescue ActiveRecord::RecordInvalid => e
      redirect_back fallback_location: kitchen_orders_path,
                    alert: e.record.errors.full_messages.to_sentence
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

    # Supprimer une demande : la saisie en double, l'erreur de séjour. Soft-delete
    # (la ligne garde son historique PaperTrail), et AUCUN email : supprimer n'est
    # pas annuler — un client qui renonce passe par « Annuler la demande », qui
    # prévient la cuisine. On revient sur l'onglet et les filtres d'où l'on vient.
    def destroy
      @order.soft_delete!(validate: false)
      redirect_to kitchen_orders_path(params.permit(*INDEX_PARAMS)), notice: "Demande supprimée."
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
      # « À couvrir » → « Confier à… » : la demande refusée repart vers la
      # nouvelle personne, qui doit à son tour dire oui (repas) ou qui l'accepte
      # en s'en chargeant (buffet, apéro).
      if @order.refused?
        @order.validation     = "pending"
        @order.refusal_reason = nil
      end
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

    # Plus de coût par prestation (epic #269) : les courses se font par lot, pour
    # plusieurs services à la fois, et la dépense s'affecte en comptabilité. Un
    # `cost` envoyé par une vieille page ne modifie donc plus rien.
    def order_params
      params.require(:meal_order).permit(:kind, :moment, :date, :people, :notes, :status,
                                         :cancellation_reason, :responsible_human_id,
                                         :contact_label, :origin)
            .merge(unit_price_cents: submitted_unit_price_cents)
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

    # Ni type ni responsable préremplis. Le type l'était par le premier type
    # activé, et le responsable par le défaut de CE type : basculer le type sans
    # toucher au responsable laissait un buffet au nom de Stéphanie — et, comme
    # `accept_when_someone_takes_it` voit un responsable nommé, ACCEPTÉ par la
    # cuisine sans que personne ne l'ait accepté. Le type se coche donc
    # explicitement, et `MealOrder#assign_default_responsible` affecte le
    # responsable à partir de la famille réellement choisie.
    # `origin: "reception"` par défaut (epic #321, phase 2) : on est sur le
    # formulaire de SAISIE MANUELLE, donc par définition celui de Malau au
    # téléphone. Les demandes venues du client arrivent par le funnel, jamais ici.
    def new_order_defaults
      { stay_id: params[:stay_id].presence, people: 1, status: "requested",
        origin: "reception" }
    end

    # Le texte libre « Pour qui ? » d'une saisie sans séjour. Vide dès qu'un
    # séjour est choisi : le nom du client fait alors foi.
    def submitted_contact_label
      params.dig(:meal_order, :contact_label).to_s.strip.presence
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

    # La saisie à plusieurs prestations (issue #265). Le séjour est en tête du
    # formulaire, les blocs derrière : un apéro, un buffet et des repas partent
    # ensemble, chacun avec son type et son statut, et la transaction est unique
    # — si une ligne est invalide, aucune n'est créée.
    def create_prestations
      blocks = submitted_blocks
      stay   = submitted_stay
      label  = submitted_contact_label
      result = Kitchen::GridSubmission.new(stay: stay, contact_label: label, blocks: blocks).run

      if result.success?
        redirect_to kitchen_orders_path,
                    notice: "#{result.orders.size} service(s) enregistré(s)."
      else
        # On réaffiche CE QUI A ÉTÉ SAISI, blocs compris : refaire trois blocs
        # parce que le deuxième manquait une case est le genre de punition qui
        # fait retourner Malau à son tableau papier.
        @order = MealOrder.new(stay_id: stay&.id, contact_label: label,
                               origin: submitted_origin)
        @prestations = blocks
        prepare_form
        flash.now[:alert] = result.error
        render :new, status: :unprocessable_entity
      end
    end

    def submitted_stay
      Stay.find_by(id: params.dig(:meal_order, :stay_id).presence || params[:stay_id].presence)
    end

    # Origine postée par le formulaire de saisie manuelle. Repli sur
    # « proposée par l'accueil » : c'est ce que ce formulaire est, et une valeur
    # forgée n'a rien à faire en base.
    def submitted_origin
      value = params.dig(:meal_order, :origin).to_s
      MealOrder::ORIGINS.include?(value) ? value : "reception"
    end

    # Les blocs postés, dans l'ordre des index. Rails rend `prestations[0][…]`
    # comme un HASH à clés-chaînes : après un retrait de bloc les index sautent
    # (0, 2, 3), d'où le tri numérique plutôt qu'une confiance dans l'ordre.
    def submitted_blocks
      params[:prestations].to_unsafe_h.sort_by { |index, _| index.to_i }
                          .each_with_index.map { |(_, raw), position| block_from(raw, position) }
    end

    def block_from(raw, position)
      attributes = raw.slice("kind", "moment", "date", "people", "notes", "status",
                             "responsible_human_id")
                      .symbolize_keys.compact_blank
      attributes[:unit_price_cents] = price_cents(raw["unit_price"])
      # L'origine vaut pour TOUTE la saisie, pas bloc par bloc : un même coup de
      # fil a une seule origine (epic #321, phase 2).
      attributes[:origin] = submitted_origin
      attributes.compact!
      apply_kitchen_acceptance(attributes)

      Kitchen::GridSubmission::Block.new(index: position, attributes: attributes,
                                         cells: raw["grid"])
    end

    # Se charger d'un buffet ou d'un apéro vaut acceptation — bloc par bloc,
    # puisque chaque bloc a son type et son responsable. La famille `repas`
    # garde sa validation par Stéphanie, elle seule cuisine.
    def apply_kitchen_acceptance(attributes)
      return if attributes[:responsible_human_id].blank?
      return if MealOrder::KIND_FAMILIES[attributes[:kind].to_s] == "repas"

      attributes[:validation] = "accepted"
      attributes[:validated_at] = Time.current
    end

    def price_cents(raw)
      return nil if raw.to_s.strip.blank?

      (raw.to_s.tr(",", ".").to_f * 100).round
    end

    def prepare_form
      @stays  = assignable_stays
      @humans = Human.where(status: "active").order(:name)
      @kinds  = MealOrder::KIND_LABELS.filter_map do |kind, label|
        [label, kind] if Kitchen::Config.enabled_kinds.include?(kind) || kind == @order.kind
      end
      @grid_days = grid_days_for(@order)
      @prestations ||= [Kitchen::GridSubmission::Block.new(index: 0, attributes: {}, cells: {})]
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
      scope = scope.of_origin(@origin) if @origin.present?
      scope
    end

    def responsible_filter
      value = params[:responsible_human_id].to_s
      value.presence && (Human.exists?(id: value) ? value : nil)
    end

    # Les filtres ont chacun leur vue (maquette du 2026-10-19) : la famille
    # dans la vue Cuisine (qui cuisine quoi), l'origine dans la vue Accueil
    # (qui relancer). Ailleurs, un paramètre resté dans l'URL filtrerait une
    # liste dont l'écran ne montre aucun sélecteur, donc sans rien expliquer.
    ORIGIN_FILTER_VIEWS = %i[reception].freeze
    FAMILY_FILTER_VIEWS = %i[kitchen].freeze

    def origin_filter
      return nil unless ORIGIN_FILTER_VIEWS.include?(@view)

      value = params[:origin].to_s
      MealOrder::ORIGINS.include?(value) ? value : nil
    end

    def family_filter
      return nil unless FAMILY_FILTER_VIEWS.include?(@view)

      value = params[:family].to_s
      MealOrder::FAMILIES.include?(value) ? value : nil
    end

    # La vue demandée ; à défaut, la dernière vue de travail ouverte sur cet
    # appareil ; à défaut, Cuisine. Les anciens onglets (« upcoming », « all »,
    # « info »…) d'un lien gardé retombent ainsi sur une vue qui existe.
    def view_param
      key = params[:view].to_s.to_sym
      return key if VIEW_KEYS.include?(key)

      remembered = cookies[VIEW_COOKIE].to_s.to_sym
      WORKING_VIEW_KEYS.include?(remembered) ? remembered : :kitchen
    end

    def remember_view
      cookies.permanent[VIEW_COOKIE] = @view.to_s if working_view?
    end

    def working_view? = WORKING_VIEW_KEYS.include?(@view)

    # Tout ce qui est encore à venir et pas annulé par le client — y compris ce
    # que la cuisine a refusé, qu'il faut couvrir. Les demandes sans date en
    # tête : elles sont encore à traiter.
    def live_rows
      @live_rows ||= base_scope.upcoming.where.not(status: "cancelled").undated_first.to_a
    end

    def decorated_live_rows
      @decorated_live_rows ||= MealOrderDecorator.decorate_collection(live_rows)
    end

    def rows_for(view)
      case view
      when :past then archive_scope.antichronological.limit(ARCHIVE_LIMIT).to_a
      when :out  then out_scope.antichronological.limit(CANCELLED_LIMIT).to_a
      end
    end

    # Les compteurs du sélecteur : ce que chaque métier a à FAIRE, pas tout ce
    # qu'il voit. Le passé et les annulés se comptent par une requête, sans la
    # limite d'affichage.
    def view_counts
      statuses = live_rows.map(&:board_status)
      { kitchen:   statuses.count("to_validate"),
        reception: statuses.count { |s| %w[to_cover inquiry].include?(s) },
        past:      archive_scope.count,
        out:       out_scope.count }
    end

    # Déjà servi. Un refus passé n'a rien été servi : il va dans « Annulés ».
    def archive_scope
      scope = base_scope.past.where.not(status: "cancelled").where.not(validation: "refused")
      return scope if @old_archives

      scope.where("date >= ?", RECENT_ARCHIVE_MONTHS.months.ago.to_date)
    end

    # Retiré du jeu : annulé par le client, ou refusé par la cuisine et passé.
    def out_scope
      base_scope.where(status: "cancelled").or(base_scope.past.where(validation: "refused"))
    end

    # Groupé par séjour, comme le tableau de Malau : un en-tête par client, et le
    # sous-total de ce qui compte vraiment (les lignes facturables).
    #
    # Les demandes SANS séjour (issue #315) se groupent par leur texte libre, une
    # entête par « pour qui » : les mettre toutes dans un même groupe vide
    # mélangerait l'école du mardi et le groupe d'anniversaire du samedi.
    def set_presenters
      @home_view = true
    end
  end
end
