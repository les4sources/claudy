# == Schema Information
#
# Table name: unavailabilities
#
#  id         :bigint           not null, primary key
#  date       :date
#  lodging_id :bigint           not null
#  created_at :datetime         not null
#  updated_at :datetime         not null
#
require 'rails_helper'

RSpec.describe Unavailability, type: :model do
  pending "add some examples to (or delete) #{__FILE__}"
end
