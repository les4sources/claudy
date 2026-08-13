# == Schema Information
#
# Table name: roles
#
#  id         :bigint           not null, primary key
#  deleted_at :datetime
#  name       :string
#  role_team  :jsonb
#  created_at :datetime         not null
#  updated_at :datetime         not null
#
# Indexes
#
#  index_roles_on_role_team  (role_team) USING gin
#
require 'rails_helper'

RSpec.describe Role, type: :model do
  pending "add some examples to (or delete) #{__FILE__}"
end
