# == Schema Information
#
# Table name: rental_items
#
#  id          :bigint           not null, primary key
#  name        :string
#  stock       :integer
#  photo       :string
#  description :text
#  deleted_at  :datetime
#  price_cents :integer
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#
require 'rails_helper'

RSpec.describe RentalItem, type: :model do
  pending "add some examples to (or delete) #{__FILE__}"
end
