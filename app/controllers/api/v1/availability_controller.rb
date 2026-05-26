module Api
  module V1
    class AvailabilityController < BaseController
      MAX_RANGE_DAYS = 92

      def index
        from = parse_date(params[:from])
        to = parse_date(params[:to])

        return render_invalid("`from` and `to` are required ISO dates (YYYY-MM-DD).") if from.nil? || to.nil?
        return render_invalid("`to` must be on or after `from`.") if to < from
        return render_invalid("Range exceeds #{MAX_RANGE_DAYS} days.") if (to - from).to_i + 1 > MAX_RANGE_DAYS

        dates = (from..to).to_a
        result = { from: from, to: to }

        unless params[:space_id].present?
          lodgings = params[:lodging_id].present? ? Lodging.where(id: params[:lodging_id]) : Lodging.all
          result[:lodgings] = lodgings.map do |lodging|
            {
              id: lodging.id,
              name: lodging.name,
              dates: dates.map { |date| { date: date, available: lodging.available_on?(date) } }
            }
          end
        end

        unless params[:lodging_id].present?
          spaces = params[:space_id].present? ? Space.where(id: params[:space_id]) : Space.all
          result[:spaces] = spaces.map do |space|
            {
              id: space.id,
              name: space.name,
              dates: dates.map { |date| { date: date, available: space.available_on?(date) } }
            }
          end
        end

        render json: result
      end

      private

      def parse_date(value)
        Date.iso8601(value.to_s)
      rescue ArgumentError
        nil
      end

      def render_invalid(message)
        render json: { error: "unprocessable_entity", message: message }, status: :unprocessable_entity
      end
    end
  end
end
