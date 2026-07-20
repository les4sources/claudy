module Humans
  class UpdateService < ServiceBase
    PreconditionFailedError = Class.new(StandardError)

    attr_reader :human

    def initialize(human:)
      @human = human
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
      attrs = human_params(params)
      # `restricted_to_experiences` appartient au compte User lié, pas au Human :
      # on l'extrait avant l'assignation des attributs du Human.
      restricted = attrs.key?(:restricted_to_experiences) ? attrs.delete(:restricted_to_experiences) : nil

      human.attributes = attrs
      human.save!

      unless restricted.nil?
        user = human.user
        user&.update!(
          restricted_to_experiences: ActiveModel::Type::Boolean.new.cast(restricted)
        )
      end

      true
    end

    private

    def human_params(params)
      params
        .require(:human)
        .permit(
          :name,
          :email,
          :summary,
          :description,
          :photo,
          :photo_cache,
          :cycle_active,
          :roles_enabled,
          :status,
          :restricted_to_experiences
        )
    end
  end
end
