module Api
  module V1
    # Serves the hand-authored OpenAPI 3 spec (config/openapi/v1.yaml) as JSON so
    # agents can ingest the full machine-readable contract.
    class OpenapiController < BaseController
      SPEC_PATH = Rails.root.join("config", "openapi", "v1.yaml").freeze

      def show
        render json: spec
      end

      private

      def spec
        if Rails.env.development?
          load_spec
        else
          @spec ||= load_spec
        end
      end

      def load_spec
        YAML.safe_load(File.read(SPEC_PATH), permitted_classes: [], aliases: true)
      end
    end
  end
end
