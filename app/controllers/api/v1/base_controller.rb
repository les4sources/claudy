module Api
  module V1
    # Base for the private agent API. Inherits from ActionController::Base
    # (not ::API) so jbuilder views render exactly like the rest of the app.
    # Reads are GET; writes are PATCH (update) and DELETE (soft-delete). CSRF
    # forgery protection is skipped (token-authenticated, no cookies) and there
    # is no layout. Write bodies are wrapped under the resource root key, e.g.
    # PATCH /api/v1/bookings/1 with { "booking": { "status": "confirmed" } }.
    class BaseController < ActionController::Base
      skip_forgery_protection
      layout false

      before_action :authenticate_agent!

      rescue_from ActiveRecord::RecordNotFound, with: :render_not_found
      rescue_from ActionController::ParameterMissing, with: :render_unprocessable

      private

      def authenticate_agent!
        token = bearer_token
        return render_unauthorized if token.blank? || valid_tokens.empty?

        authorized = valid_tokens.any? { |candidate| ActiveSupport::SecurityUtils.secure_compare(token, candidate) }
        render_unauthorized unless authorized
      end

      def bearer_token
        request.authorization.to_s[/\ABearer\s+(.+)\z/i, 1]
      end

      def valid_tokens
        @valid_tokens ||= ENV.fetch("AGENT_API_TOKEN", "").split(",").map(&:strip).reject(&:empty?)
      end

      def render_unauthorized
        render json: { error: "unauthorized", message: "Missing or invalid bearer token." }, status: :unauthorized
      end

      def render_not_found
        render json: { error: "not_found" }, status: :not_found
      end

      def render_unprocessable(exception)
        render json: { error: "unprocessable_entity", message: exception.message }, status: :unprocessable_entity
      end

      # Render a 422 with the failed record's validation messages.
      def render_invalid(record)
        render json: { error: "unprocessable_entity", messages: record.errors.full_messages },
               status: :unprocessable_entity
      end

      # Paginate an ActiveRecord relation using will_paginate.
      def paginate(scope)
        per_page = params.fetch(:per_page, 50).to_i
        per_page = 50 if per_page <= 0
        per_page = [per_page, 200].min
        scope.paginate(page: params[:page], per_page: per_page)
      end
    end
  end
end
