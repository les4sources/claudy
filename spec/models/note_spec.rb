# == Schema Information
#
# Table name: notes
#
#  id         :bigint           not null, primary key
#  body       :text
#  date       :date
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  deleted_at :datetime
#  color      :string
#
require 'rails_helper'

RSpec.describe Note, type: :model do
  pending "add some examples to (or delete) #{__FILE__}"
end
