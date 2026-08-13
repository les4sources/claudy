# == Schema Information
#
# Table name: human_roles
#
#  id         :bigint           not null, primary key
#  date       :date
#  status     :integer          default(1), not null
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  human_id   :bigint           not null
#  role_id    :bigint           not null
#
# Indexes
#
#  index_human_roles_on_human_id  (human_id)
#  index_human_roles_on_role_id   (role_id)
#
# Foreign Keys
#
#  fk_rails_...  (human_id => humans.id)
#  fk_rails_...  (role_id => roles.id)
#
require 'rails_helper'

RSpec.describe HumanRole, type: :model do
  pending "add some examples to (or delete) #{__FILE__}"
end
