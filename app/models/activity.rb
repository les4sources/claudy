# == Schema Information
#
# Table name: activities
#
#  id             :integer          not null, primary key
#  trackable_type :string
#  trackable_id   :integer
#  owner_type     :string
#  owner_id       :integer
#  key            :string
#  parameters     :text
#  recipient_type :string
#  recipient_id   :integer
#  created_at     :datetime         not null
#  updated_at     :datetime         not null
#
class Activity < PublicActivity::Activity
  scope :stays_without_drafts, -> {
    where(trackable_type: 'Stay', trackable_id: Stay.draft_excluded.select(:id))
  }
end 
