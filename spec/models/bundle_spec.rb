# == Schema Information
#
# Table name: bundles
#
#  id         :bigint           not null, primary key
#  name       :string
#  position   :integer
#  project_id :bigint
#  team_id    :bigint
#  deleted_at :datetime
#  created_at :datetime         not null
#  updated_at :datetime         not null
#
require 'rails_helper'

RSpec.describe Bundle, type: :model do
  pending "add some examples to (or delete) #{__FILE__}"
end
