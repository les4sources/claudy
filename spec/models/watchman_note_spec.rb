require 'rails_helper'

# == Schema Information
#
# Table name: watchman_notes
#
#  id         :bigint           not null, primary key
#  date       :date
#  note       :text
#  created_at :datetime         not null
#  updated_at :datetime         not null
#
# Indexes
#
#  index_watchman_notes_on_date  (date)
#
RSpec.describe WatchmanNote, type: :model do
  pending "add some examples to (or delete) #{__FILE__}"
end
