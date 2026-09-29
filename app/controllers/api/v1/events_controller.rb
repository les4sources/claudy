module Api
  module V1
    # Les événements (epic #245) — ce que le site les4sources.be publie dans
    # son agenda, et ce que l'équipe prépare côté finances.
    #
    # L'API existe pour qu'un agent puisse encoder et publier des événements
    # sans passer par le formulaire : reprendre l'agenda de l'ancien site,
    # annoncer une nouvelle date d'une série, marquer une date complète.
    #
    # Lecture : brouillons compris (l'API publique, elle, ne montre que le
    # publié). Écriture : POST est un UPSERT sur `slug` — rejouer le même appel
    # met l'événement à jour au lieu d'en créer un second, et `meta.created` dit
    # lequel des deux s'est produit. `published: true` publie sur le site (le
    # slug est alors figé, comme depuis l'admin) ; `image_url` télécharge
    # l'image ; `category` accepte le slug d'une catégorie.
    #
    # Les organisateurs, les frais et le règlement restent dans l'admin : ce
    # sont des décisions d'argent, pas de la publication.
    class EventsController < BaseController
      before_action :get_event, only: [:show, :update, :destroy]
      before_action :set_date_range, only: [:index]

      def index
        scope = Event.includes(:event_category, image_attachment: :blob)
        scope = scope.where("events.ends_at >= ?", @from.beginning_of_day) if @from
        scope = scope.where("events.starts_at <= ?", @to.end_of_day) if @to
        scope = filter_published(scope)
        scope = scope.where(slug: params[:slug].to_s.parameterize) if params[:slug].present?
        if params[:category].present?
          scope = scope.joins(:event_category).where(event_categories: { slug: params[:category] })
        end
        scope = scope.where("events.name ILIKE ?", "%#{Event.sanitize_sql_like(params[:q])}%") if params[:q].present?

        @events = paginate(scope.order(:starts_at, :id))
      end

      def show; end

      def create
        attributes = event_params
        slug = attributes[:slug].to_s.parameterize.presence
        @event = (Event.find_by(slug: slug) if slug) || Event.new
        @created = @event.new_record?
        save_event(attributes, status: @created ? :created : :ok)
      end

      def update
        save_event(event_params, status: :ok)
      end

      def destroy
        @event.soft_delete!(validate: false)
        head :no_content
      end

      private

      def get_event
        @event = Event.find(params[:id])
      end

      # Applique les attributs, l'image et la publication, puis enregistre — ou
      # rien du tout : une image injoignable n'écrit pas un événement à moitié.
      def save_event(attributes, status:)
        assign(attributes)
        return if performed?

        if @event.save
          @event.reload
          render :show, status: status
        else
          render_invalid(@event)
        end
      end

      def assign(attributes)
        attributes = attributes.to_h.symbolize_keys
        published = attributes.delete(:published)
        category = attributes.delete(:category)
        image_url = attributes.delete(:image_url)
        attributes[:url] = attributes.delete(:registration_url) if attributes.key?(:registration_url)
        remove_image = attributes.delete(:remove_image)

        %i[starts_at ends_at].each do |key|
          next unless attributes.key?(key)

          attributes[key] = parse_time(attributes[key], key)
          return if performed?
        end

        if category.present?
          found = EventCategory.find_by(slug: category.to_s)
          return render_errors("Catégorie inconnue : #{category}. Voir GET /api/v1/event_categories.") unless found

          attributes[:event_category_id] = found.id
        end

        @event.assign_attributes(attributes)

        unless published.nil?
          @event.published_at = ActiveModel::Type::Boolean.new.cast(published) ? (@event.published_at || Time.current) : nil
        end

        if ActiveModel::Type::Boolean.new.cast(remove_image)
          @event.image.detach
        elsif image_url.present?
          attach_remote_image(image_url)
        end
      end

      # « 2026-10-03 » → minuit (journée entière, comme le formulaire sans
      # heure) ; « 2026-10-03T09:30 » → heure de Bruxelles ; un décalage
      # explicite (« +02:00 ») est respecté.
      def parse_time(value, key)
        return nil if value.blank?

        Time.zone.parse(value.to_s) || raise(ArgumentError)
      rescue ArgumentError
        render_errors("#{key} invalide : attendu AAAA-MM-JJ ou une date-heure ISO 8601.")
        nil
      end

      def attach_remote_image(url)
        download = Events::RemoteImage.new(url).fetch
        @event.image.attach(io: download.io, filename: download.filename, content_type: download.content_type)
      rescue Events::RemoteImage::Error => e
        render_errors("image_url : #{e.message}")
      end

      def filter_published(scope)
        return scope if params[:published].blank?

        ActiveModel::Type::Boolean.new.cast(params[:published]) ? scope.published : scope.draft
      end

      # `from` / `to` : événements qui se terminent après `from` et commencent
      # avant `to`, bornes incluses — ceux qui touchent la période.
      def set_date_range
        @from = params[:from].present? ? Date.parse(params[:from]) : nil
        @to = params[:to].present? ? Date.parse(params[:to]) : nil
      rescue Date::Error
        render_errors("Paramètres `from`/`to` invalides : attendu AAAA-MM-JJ.")
      end

      def render_errors(message)
        render json: { error: "unprocessable_entity", message: message }, status: :unprocessable_entity
      end

      def event_params
        params.require(:event).permit(
          :name, :summary, :starts_at, :ends_at, :location, :price_text, :registration_url, :status,
          :public_description, :event_category_id, :category, :team_id, :slug, :published,
          :image, :image_url, :remove_image
        )
      end
    end
  end
end
