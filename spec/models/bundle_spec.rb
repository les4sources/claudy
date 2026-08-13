# == Schema Information
#
# Table name: bundles
#
#  id         :bigint           not null, primary key
#  deleted_at :datetime
#  name       :string
#  position   :integer
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  project_id :bigint
#  team_id    :bigint
#
# Indexes
#
#  index_bundles_on_project_id  (project_id)
#  index_bundles_on_team_id     (team_id)
#
# Foreign Keys
#
#  fk_rails_...  (project_id => projects.id)
#  fk_rails_...  (team_id => teams.id)
#
require 'rails_helper'

RSpec.describe Bundle, type: :model do
  pending "add some examples to (or delete) #{__FILE__}"
end
