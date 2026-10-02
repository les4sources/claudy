# La fiche d'une plante nourricière sur la carte (epic #348, phase 7).
#
# Même mécanique que la fiche d'un objet (`MapFeaturesController`) : la carte
# ouvre `GET /map/plants/:id` dans la Turbo Frame du panneau, et chaque geste
# (enregistrer, retirer une photo, retirer de la carte, supprimer) répond en
# Turbo Stream qui remplace la fiche, sans recharger la carte.
#
# Espèce et variété arrivent par leur NOM (`species_name`, `variety_name`) : la
# fiche propose les existantes en autocomplétion et crée les autres à la volée
# (« Créer “Néflier” »). Le prix d'achat arrive en euros, la base garde des cents.
class PlantsController < BaseController
  PANEL_FRAME = MapFeaturesController::PANEL_FRAME

  UNPLACED_FRAME = "plants_unplaced".freeze

  before_action :get_plant, except: %i[index unplaced new create identify]

  # GET /map/plantes — toutes les plantes du domaine, en liste : recherche,
  # filtres statut, santé, zone, strate, placée ou non ; tri par numéro. Les
  # compteurs de tête portent sur tout le domaine, pas sur le filtre.
  def index
    @counts = {
      total: Plant.count,
      placed: Plant.alive.placed.count,
      to_place: Plant.alive.to_place.count,
      dead: Plant.where(status: Plant::DEAD).count
    }
    @zones = Plant.zones
    @filters = {
      q: params[:q].to_s.squish.presence,
      status: params[:status].presence_in(Plant::STATUSES.keys),
      health: params[:health].presence_in(Plant::HEALTHS.keys),
      zone: params[:zone].presence_in(@zones),
      stratum: params[:stratum].presence_in(Plant::STRATA.keys),
      placed: params[:placed].presence_in(%w[yes no])
    }
    scope = Plant.search(@filters[:q]).in_zone(@filters[:zone])
    scope = scope.with_status(@filters[:status]) if @filters[:status]
    scope = scope.where(health: @filters[:health]) if @filters[:health]
    scope = scope.where(stratum: @filters[:stratum]) if @filters[:stratum]
    scope = scope.placed if @filters[:placed] == "yes"
    scope = scope.alive.to_place if @filters[:placed] == "no"
    @plants = scope.ordered.includes(:plant_species, :plant_variety).with_attached_photos.to_a
  end

  # GET /map/plants/unplaced — le tiroir « Placer des plantes » : les plantes
  # vivantes sans point, filtrables par zone et par recherche, dans l'ordre des
  # numéros. `selected` garde la plante en cours de placement en surbrillance
  # quand la liste se recharge.
  def unplaced
    base = Plant.alive.to_place
    @total = base.count
    @zones = base.zones
    @zone = params[:zone].to_s.squish.presence
    @query = params[:q].to_s.squish.presence
    @selected_id = params[:selected].to_s[/\A\d+\z/]&.to_i
    @plants = base.in_zone(@zone).search(@query).ordered
                  .includes(:plant_species, :plant_variety).with_attached_photos.to_a
    render layout: false
  end

  def show
    render :show, layout: false
  end

  # GET /map/plants/new — la fiche d'une plante qu'on vient de mettre en terre :
  # plantée aujourd'hui, à placer ensuite. `zone` pré-remplit la zone.
  def new
    @plant = Plant.new(status: "planted", planted_on: Date.current, zone: params[:zone].to_s.squish.presence)
    render :show, layout: false
  end

  # POST /map/plants — crée la plante (espèce et variété par leur nom, créées au
  # besoin). Elle naît sans point : la fiche rouverte propose « Placer sur la
  # carte » et « Je suis devant ».
  def create
    @plant = Plant.new(created_by: current_user)
    saved = Plant.transaction do
      assign_plant
      (@assign_errors.empty? && @plant.save) || raise(ActiveRecord::Rollback)
    end

    if saved
      render_panel(saved: true, created: true)
    else
      @plant.valid? if @assign_errors.any?
      @assign_errors.each { |message| @plant.errors.add(:base, message) }
      render_panel(status: :unprocessable_entity)
    end
  end

  def update
    saved = Plant.transaction do
      assign_plant
      (@assign_errors.empty? && @plant.save) || raise(ActiveRecord::Rollback)
    end

    if saved
      render_panel(saved: true)
    else
      # Une erreur d'assignation (prix illisible, variété sans espèce) a évité
      # l'enregistrement : on valide quand même, pour tout montrer d'un coup.
      @plant.valid? if @assign_errors.any?
      @assign_errors.each { |message| @plant.errors.add(:base, message) }
      render_panel(status: :unprocessable_entity)
    end
  end

  # POST /map/plants/identify — « Quelle est cette plante ? » : une à cinq
  # photos du même individu, et les espèces probables selon Pl@ntNet, à valider
  # ou refuser dans la fiche (`plant-identify`). Rien n'est enregistré sur la
  # plante ici : l'espèce retenue remplit le champ Espèce, les photos gardées
  # rejoignent la plante à l'enregistrement de la fiche.
  def identify
    @identification = PlantNet::Identify.new(files: params[:photos]).run!
    render partial: "plants/identification", locals: { identification: @identification }
  rescue PlantNet::Identify::Invalid, PlantNet::Client::Error => e
    render partial: "plants/identification", locals: { error: e.message }, status: :unprocessable_content
  end

  # POST /map/plants/:id/place — pose la plante sur la carte, ou déplace son
  # point (clic sur la carte, « Je suis devant », glisser). La carte appelle en
  # JSON et enchaîne elle-même ; en Turbo Stream, la fiche se rouvre placée.
  # Une position illisible ou hors du globe répond 422 sans rien écrire.
  def place
    latitude = coordinate(params[:latitude])
    longitude = coordinate(params[:longitude])
    unless latitude&.between?(-90, 90) && longitude&.between?(-180, 180)
      return placement_error("Position illisible : il faut une latitude et une longitude.")
    end

    moved = @plant.placed?
    @plant.place!(latitude: latitude, longitude: longitude, user: current_user)
    return render(json: placement_json.merge(moved: moved)) if request.format.json?

    render_panel(saved: true)
  rescue ActiveRecord::RecordInvalid => e
    placement_error(e.record.errors.full_messages.to_sentence)
  end

  # « Retirer de la carte » : le point disparaît, la plante redevient à placer.
  # La fiche reste ouverte et dit à la carte quelle couche recharger. En JSON :
  # l'« Annuler » du mode Placement.
  def unplace
    layer_id = @plant.map_feature&.map_layer_id
    @plant.unplace!
    return render(json: placement_json.merge(layer_id: layer_id)) if request.format.json?

    render_panel(unplaced_layer_id: layer_id)
  end

  # Soft-delete : la plante emporte son point (`after_soft_delete`). Le marqueur
  # est celui de la fiche d'un objet : la carte ferme la fiche et recharge la
  # couche.
  def destroy
    layer_id = @plant.map_feature&.map_layer_id || MapLayer.for_kind(:plants).id
    @plant.soft_delete!(validate: false)
    marker = helpers.tag.div(hidden: true, data: { feature_deleted: @plant.map_feature_id || "plant-#{@plant.id}",
                                                   layer_id: layer_id })
    respond_to do |format|
      format.turbo_stream { render turbo_stream: turbo_stream.update(PANEL_FRAME, marker) }
      format.html { redirect_to map_path }
    end
  end

  def destroy_photo
    @plant.photos.find(params[:photo_id]).purge_later
    @plant.reload
    render_panel
  end

  private

  def set_presenters
    @menu_presenter = Components::MenuPresenter.new(active_primary: "map")
  end

  def get_plant
    @plant = Plant.includes(:plant_species, :plant_variety, :map_feature).find(params[:id])
  end

  def plant_params
    params.require(:plant).permit(:name, :number, :zone, :status, :health, :production, :habit, :stratum,
                                  :population, :stock_type, :plant_count, :nursery, :purchase_price,
                                  :planted_on, :planted_year, :altitude, :notion_url, :notes,
                                  :species_name, :species_latin_name, :species_family, :variety_name, photos: [])
  end

  def assign_plant
    attrs = plant_params
    @assign_errors = []
    @typed_names = attrs.slice(:species_name, :variety_name).to_h.symbolize_keys

    simple = attrs.except(:species_name, :species_latin_name, :species_family, :variety_name, :purchase_price, :photos, :number)
    @plant.assign_attributes(simple)
    # « #42 » comme « 42 », « 9,1 » comme « 9.1 ».
    @plant.number = attrs[:number].to_s.strip.delete_prefix("#").tr(",", ".").presence if attrs.key?(:number)
    # La date fait foi pour l'année ; l'année seule reste possible (import Notion).
    @plant.planted_year = @plant.planted_on.year if @plant.planted_on
    assign_price(attrs[:purchase_price]) if attrs.key?(:purchase_price)
    assign_species(attrs) if attrs.key?(:species_name) || attrs.key?(:variety_name)

    photos = Array(attrs[:photos]).compact_blank
    @plant.photos.attach(photos) if photos.any?
  end

  # « 12,50 », « 12.5 », « 12 € » → 1250 cents. Vide = pas de prix.
  def assign_price(value)
    text = value.to_s.delete("€").delete(" ").tr(",", ".")
    return @plant.purchase_price_cents = nil if text.blank?

    euros = BigDecimal(text, exception: false)
    if euros.nil? || euros.negative?
      @assign_errors << "Prix d'achat illisible : « #{value} » (en euros, par exemple 24,50)"
    else
      @plant.purchase_price_cents = (euros * 100).round.to_i
    end
  end

  # L'espèce par son nom (créée si besoin), puis la variété au sein de cette
  # espèce. Vider l'espèce retire aussi la variété. Une espèce retenue par
  # identification photo apporte son nom latin et sa famille : ils ne servent
  # qu'à créer une espèce nouvelle, jamais à réécrire une existante.
  def assign_species(attrs)
    species_name = attrs.key?(:species_name) ? attrs[:species_name].to_s.squish : @plant.plant_species&.name.to_s
    variety_name = attrs[:variety_name].to_s.squish
    botany = { latin_name: attrs[:species_latin_name], family: attrs[:species_family] }.transform_values { |v| v.to_s.squish }.compact_blank

    species = species_name.present? ? PlantSpecies.find_or_create_by_name!(species_name, created_by: current_user, **botany) : nil
    @plant.plant_species = species

    if variety_name.blank?
      @plant.plant_variety = nil
    elsif species
      @plant.plant_variety = species.find_or_create_variety!(variety_name)
    else
      @plant.plant_variety = nil
      @assign_errors << "Une variété appartient à une espèce : indiquez d'abord l'espèce de « #{variety_name} »"
    end
  end

  # « 50,34 » comme « 50.34 » ; rien d'infini ni de NaN.
  def coordinate(value)
    number = Float(value.to_s.strip.tr(",", "."), exception: false)
    number if number&.finite?
  end

  def placement_json
    { plant_id: @plant.id, name: @plant.display_name, status: @plant.status,
      map_feature_id: @plant.map_feature_id, layer_id: @plant.map_feature&.map_layer_id,
      latitude: @plant.latitude, longitude: @plant.longitude,
      remaining: Plant.alive.to_place.count }
  end

  def placement_error(message)
    respond_to do |format|
      format.json { render json: { error: message }, status: :unprocessable_content }
      format.any { render plain: message, status: :unprocessable_content }
    end
  end

  def render_panel(status: :ok, **locals)
    stream = turbo_stream.update(PANEL_FRAME, partial: "plants/panel",
                                              locals: { plant: @plant, typed_names: @typed_names || {}, **locals })
    respond_to do |format|
      format.turbo_stream { render turbo_stream: stream, status: status }
      format.html { redirect_to map_path(feature: @plant.map_feature_id) }
    end
  end
end
