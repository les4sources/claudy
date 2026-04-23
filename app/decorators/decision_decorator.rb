class DecisionDecorator < ApplicationDecorator
  delegate_all
  decorates_association :recorded_by
  decorates_association :gathering, with: GatheringDecorator
  decorates_association :agenda_item

  def taken_at_label
    h.l(object.taken_at, format: :long)
  end

  def recorded_by_label
    object.recorded_by&.name || "—"
  end

  def body_plain
    return nil unless object.body.present?
    object.body.to_plain_text
  end

  def body_excerpt(limit: 200)
    text = body_plain
    return nil if text.blank?
    h.truncate(text, length: limit, separator: " ")
  end

  def gathering_label
    return nil unless object.gathering
    "#{object.gathering.gathering_category.name} du #{h.l(object.gathering.starts_at.to_date)}"
  end
end
