# == Schema Information
#
# Table name: human_roles
#
#  id         :bigint           not null, primary key
#  human_id   :bigint           not null
#  role_id    :bigint           not null
#  date       :date
#  created_at :datetime         not null
#  updated_at :datetime         not null
#
require 'rails_helper'

RSpec.describe HumanRole, type: :model do
  pending "add some examples to (or delete) #{__FILE__}"
end
