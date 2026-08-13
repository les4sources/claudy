# == Schema Information
#
# Table name: services
#
#  id          :bigint           not null, primary key
#  deleted_at  :datetime
#  description :text
#  name        :string
#  photo       :string
#  price_cents :integer
#  summary     :string
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#  human_id    :bigint
#
# Indexes
#
#  index_services_on_human_id  (human_id)
#
# Foreign Keys
#
#  fk_rails_...  (human_id => humans.id)
#
require 'rails_helper'

RSpec.describe Service, type: :model do
  pending "add some examples to (or delete) #{__FILE__}"
end
