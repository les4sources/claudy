module Gatherings
  class UpdateService < ServiceBase
    attr_reader :gathering

    def initialize(gathering:)
      @gathering = gathering
      @report_errors = true
    end

    def run(params = {})
      context = { params: params }

      catch_error(context: context) do
        run!(params)
      end
    end

    def run!(params = {})
      gathering.attributes = gathering_params(params)
      gathering.starts_at = parsed_starts_at
      gathering.ends_at = parsed_ends_at
      gathering.save!
      true
    end

    private

    def gathering_params(params)
      params
        .require(:gathering)
        .permit(
          :name,
          :gathering_category_id,
          :location,
          :notes,
          :starts_at_date,
          :starts_at_time,
          :ends_at_date,
          :ends_at_time
        )
    end

    def parsed_starts_at
      Time.zone.parse("#{gathering.starts_at_date} #{gathering.starts_at_time}")
    end

    def parsed_ends_at
      Time.zone.parse("#{gathering.ends_at_date} #{gathering.ends_at_time}")
    end
  end
end
