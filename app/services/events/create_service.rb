module Events
  class CreateService < ServiceBase
    attr_reader :event

    def initialize
      @event = Event.new
      @report_errors = true
    end

    def run(params = {})
      context = {
        params: params,
      }

      catch_error(context: context) do
        run!(params)
      end
    end

    def run!(params = {})
      event.attributes = event_params(params)
      event.starts_at = set_starts_at
      event.ends_at = set_ends_at
      event.save!
      # Les organisateurs vivent dans leur propre table : le formulaire les
      # envoie à part, hors des attributs de l'événement.
      Events::SyncOrganizers.new(event: event).run(params[:event][:organizers])
      copy_image_from_source
      true
    end

    private

    def event_params(params)
      params
        .require(:event)
        .permit(
          :attendees,
          :duplicate_of_id,
          :ends_at_date,
          :ends_at_time,
          :event_category_id,
          :image,
          :location,
          :name,
          :notes,
          :price_text,
          :public_description,
          :sales_amount,
          :slug,
          :starts_at_date,
          :starts_at_time,
          :status,
          :summary,
          :url,
          :team_id,
          :organizer_share_percent
        )
    end

    def set_starts_at
      Time.zone.parse("#{event.starts_at_date} #{event.starts_at_time}")
    end

    def set_ends_at
      Time.zone.parse("#{event.ends_at_date} #{event.ends_at_time}")
    end

    # Duplication (`Events::DuplicateService`) : l'image de l'événement source
    # est reprise si aucune nouvelle image n'a été envoyée. Le blob est
    # partagé — Claudy ne supprime jamais physiquement un événement
    # (soft-delete), le fichier ne disparaît donc pas sous la copie.
    def copy_image_from_source
      return if event.duplicate_of_id.blank? || event.image.attached?

      source = Event.find_by(id: event.duplicate_of_id)
      return unless source&.image&.attached?

      event.image.attach(source.image.blob)
    end
  end
end
