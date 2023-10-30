module RentalItems
  class UpdateService < ServiceBase
    PreconditionFailedError = Class.new(StandardError)

    attr_reader :rental_item

    def initialize(rental_item:)
      @rental_item = rental_item
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
      rental_item.attributes = rental_item_params(params)
      rental_item.save!
      true
    end

    private

    def rental_item_params(params)
      params
        .require(:rental_item)
        .permit(
          :name,
          :description,
          :price,
          :photo,
          :photo_cache,
          :price,
          :stock
        )
    end
  end
end
