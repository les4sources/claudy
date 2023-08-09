# == Schema Information
#
# Table name: products
#
#  id          :integer          not null, primary key
#  name        :string
#  stock       :integer
#  photo       :string
#  description :text
#  deleted_at  :datetime
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#  price_cents :integer
#
require 'rails_helper'

RSpec.describe Product, type: :model do
  pending "add some examples to (or delete) #{__FILE__}"
end
