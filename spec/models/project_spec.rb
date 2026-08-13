# == Schema Information
#
# Table name: projects
#
#  id          :bigint           not null, primary key
#  deleted_at  :datetime
#  description :text
#  due_date    :date
#  name        :string
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#  human_id    :bigint           not null
#
# Indexes
#
#  index_projects_on_human_id  (human_id)
#
# Foreign Keys
#
#  fk_rails_...  (human_id => humans.id)
#
require 'rails_helper'

RSpec.describe Project, type: :model do
  pending "add some examples to (or delete) #{__FILE__}"
end
