class AgendaItemDecorator < ApplicationDecorator
  delegate_all
  decorates_association :author
  decorates_association :gathering

  def status_class
    if object.completed?
      "bg-stone-50 border-stone-200 text-stone-500"
    else
      "bg-white border-stone-200 hover:border-emerald-300"
    end
  end

  def title_class
    object.completed? ? "line-through text-stone-400" : "text-stone-900"
  end

  def author_label
    object.author&.name || "—"
  end

  def carrier_label
    object.carrier&.name || "Non assigné"
  end

  # Shown in the edit modal: who added the point and when.
  def added_meta
    by = object.author&.name || "—"
    "Ajouté par #{by} le #{h.l(object.created_at, format: :long)}"
  end

  def description_plain
    return nil unless object.description.present?
    object.description.to_plain_text
  end

  def description_excerpt(limit: 140)
    text = description_plain
    return nil if text.blank?
    h.truncate(text, length: limit, separator: " ")
  end

  def has_attachments?
    object.attachments.attached? ||
      (object.description.present? && object.description.body.attachables.any?)
  end

  def attachments_count
    object.attachments.count
  end
end
