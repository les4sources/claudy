module Events
  class UpdateService < ServiceBase
    PreconditionFailedError = Class.new(StandardError)

    attr_reader :event

    def initialize(event:)
      @event = event
      @report_errors = true
    end

    def run(params = {})
      context = {
        params: params
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
      true
    end

    private

    def event_params(params)
      params
        .require(:event)
        .permit(
          :attendees,
          :ends_at_date,
          :ends_at_time,
          :event_category_id,
          :name,
          :notes,
          :sales_amount,
          :starts_at_date,
          :starts_at_time,
          :status,
          :url
        )
    end

    def set_starts_at
      Time.zone.parse("#{event.starts_at_date} #{event.starts_at_time}")
    end

    def set_ends_at
      Time.zone.parse("#{event.ends_at_date} #{event.ends_at_time}")
    end
  end
end
