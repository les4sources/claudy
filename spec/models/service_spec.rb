# == Schema Information
#
# Table name: services
#
#  id          :integer          not null, primary key
#  name        :string
#  human_id    :integer
#  summary     :string
#  description :text
#  photo       :string
#  deleted_at  :datetime
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#  price_cents :integer
#
require 'rails_helper'

RSpec.describe Service, type: :model do
  pending "add some examples to (or delete) #{__FILE__}"
end
