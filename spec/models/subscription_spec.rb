# == Schema Information
#
# Table name: subscriptions
#
#  id         :bigint           not null, primary key
#  email      :string
#  newsletter :boolean
#  created_at :datetime         not null
#  updated_at :datetime         not null
#
require 'rails_helper'

RSpec.describe Subscription, type: :model do
  pending "add some examples to (or delete) #{__FILE__}"
end
