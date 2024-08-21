class Activity < PublicActivity::Activity
  scope :stays_without_drafts, -> {
    where(trackable_type: 'Stay', trackable_id: Stay.draft_excluded.select(:id))
  }
end