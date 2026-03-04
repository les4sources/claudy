module Cycles
  class CreateService < ServiceBase
    attr_reader :cycle

    def initialize
      @cycle = Cycle.new
      @report_errors = true
    end

    def run(params = {})
      catch_error(context: { params: params }) { run!(params) }
    end

    def run!(params = {})
      cycle.attributes = cycle_params(params)
      cycle.save!
      true
    end

    private

    def cycle_params(params)
      params.require(:cycle).permit(:name, :start_date, :end_date)
    end
  end
end
