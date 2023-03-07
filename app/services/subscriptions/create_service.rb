module Subscriptions
  class CreateService < ServiceBase
    attr_reader :subscription

    def initialize
      @subscription = Subscription.new
      @report_errors = true
    end

    def run(email:)
      context = {
        email: email
      }

      catch_error(context: context) do
        run!(email: email)
      end
    end

    def run!(email:)
      @subscription.email = email
      @subscription.newsletter = true
      @subscription.save
      true
    end
  end
end
