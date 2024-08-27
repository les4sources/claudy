# == Schema Information
#
# Table name: customers
#
#  id         :bigint           not null, primary key
#  firstname  :string
#  lastname   :string
#  phone      :string
#  email      :string
#  notes      :text
#  created_at :datetime         not null
#  updated_at :datetime         not null
#
class Customer < ApplicationRecord

	has_many :stays

end