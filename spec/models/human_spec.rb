# == Schema Information
#
# Table name: humans
#
#  id          :bigint           not null, primary key
#  name        :string
#  email       :string
#  photo       :string
#  summary     :string
#  description :text
#  deleted_at  :datetime
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#  status      :string           default("active")
#
require 'rails_helper'

RSpec.describe Human, type: :model do
  pending "add some examples to (or delete) #{__FILE__}"
end
