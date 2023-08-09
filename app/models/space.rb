# == Schema Information
#
# Table name: spaces
#
#  id          :integer          not null, primary key
#  name        :string
#  description :text
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#  code        :string
#  deleted_at  :datetime
#
class Space < ApplicationRecord
  has_many :space_reservations

  has_soft_deletion default_scope: true
end
