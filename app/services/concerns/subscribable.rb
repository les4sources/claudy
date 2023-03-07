module Subscribable
  extend ActiveSupport::Concern

  private

  def create_subscription(from:)
    return if !from.email.present?
    return if from.newsletter_subscription != "1"
    Subscriptions::CreateService.new.run(email: from.email)
  end
end
