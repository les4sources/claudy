module Gatherings
  class CreateService < ServiceBase
    attr_reader :gathering

    def initialize
      @gathering = Gathering.new
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
      # Après la sauvegarde : un rassemblement neuf n'a pas d'id avant, et un
      # rattachement à un rassemblement invalide n'aurait rien à quoi se lier.
      Gatherings::SyncTeams.new(gathering: gathering).run!(submitted_team_ids(params))
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

    # `nil` quand la clé est absente : seule une soumission du formulaire des
    # pôles a le droit d'en détacher un (cf. `Gatherings::SyncTeams`).
    def submitted_team_ids(params)
      params.require(:gathering).permit(team_ids: [])[:team_ids]
    end

    def parsed_starts_at
      Time.zone.parse("#{gathering.starts_at_date} #{gathering.starts_at_time}")
    end

    def parsed_ends_at
      Time.zone.parse("#{gathering.ends_at_date} #{gathering.ends_at_time}")
    end
  end
end
