module Products
  class CreateService < ServiceBase
    attr_reader :product

    def initialize
      @product = Product.new
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
      product.attributes = product_params(params)
      product.save!
      true
    end

    private

    def product_params(params)
      params
        .require(:product)
        .permit(
          :name,
          :price,
          :stock,
          :photo,
          :description
        )
    end
  end
end
