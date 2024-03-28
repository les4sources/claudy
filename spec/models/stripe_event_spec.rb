# == Schema Information
#
# Table name: stripe_events
#
#  id         :bigint           not null, primary key
#  webhook_id :string
#  event_type :string
#  object_id  :string
#  created_at :datetime         not null
#  updated_at :datetime         not null
#
require 'rails_helper'

RSpec.describe StripeEvent, type: :model do
  pending "add some examples to (or delete) #{__FILE__}"
end
