# == Schema Information
#
# Table name: experiences
#
#  id                :bigint           not null, primary key
#  name              :string
#  human_id          :bigint
#  summary           :string
#  description       :text
#  photo             :string
#  deleted_at        :datetime
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#  price_cents       :integer
#  fixed_price_cents :integer          default(0)
#  min_participants  :integer
#  max_participants  :integer
#  duration          :string
#
require 'rails_helper'

RSpec.describe Experience, type: :model do
  pending "add some examples to (or delete) #{__FILE__}"
end
