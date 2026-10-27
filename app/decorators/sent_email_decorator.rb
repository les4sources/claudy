class SentEmailDecorator < ApplicationDecorator
  delegate_all

  DELIVERY_ISSUE_LABELS = {
    "bounce" => "Non remis : adresse refusée",
    "soft_bounce" => "Non remis : refus temporaire",
    "complaint" => "Signalé comme spam"
  }.freeze

  # Le problème de remise signalé par SES, en clair (nil si aucun).
  def delivery_issue_label
    DELIVERY_ISSUE_LABELS[delivery_issue]
  end
end
