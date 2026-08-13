# == Schema Information
#
# Table name: tasks
#
#  id          :bigint           not null, primary key
#  deleted_at  :datetime
#  description :text
#  due_date    :date
#  name        :string
#  status      :string
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#  bundle_id   :bigint           not null
#  project_id  :bigint           not null
#
# Indexes
#
#  index_tasks_on_bundle_id   (bundle_id)
#  index_tasks_on_project_id  (project_id)
#
# Foreign Keys
#
#  fk_rails_...  (bundle_id => bundles.id)
#  fk_rails_...  (project_id => projects.id)
#
require 'rails_helper'

RSpec.describe Task, type: :model do
  pending "add some examples to (or delete) #{__FILE__}"
end
