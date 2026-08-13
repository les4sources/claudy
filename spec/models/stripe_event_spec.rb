# == Schema Information
#
# Table name: stripe_events
#
#  id         :bigint           not null, primary key
#  event_type :string
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  object_id  :string
#  webhook_id :string
#
require 'rails_helper'

RSpec.describe StripeEvent, type: :model do
  pending "add some examples to (or delete) #{__FILE__}"
end
