# L'affichage des propositions de tri (messagerie, phase 1). Une valeur
# trouvée par le code ne se discute pas ; une valeur choisie par Jev dit à quel
# point il est sûr, pour qu'on sache ce qu'il faut relire.
module MailMessagesHelper
  NATURE_LABELS = {
    "invoice" => "Facture", "reminder" => "Rappel", "administrative" => "Administratif",
    "marketing" => "Publicité", "other" => "Autre"
  }.freeze

  def mail_nature_label(message) = NATURE_LABELS[message.triage.dig("nature", "value")]

  def mail_confidence_badge(field)
    return if field.blank?

    label, classes = if field["source"] == "code"
                       ["reconnu", "bg-green-50 text-green-700 ring-green-200"]
                     elsif field["confidence"].to_f >= 0.85
                       ["probable", "bg-blue-50 text-blue-700 ring-blue-200"]
                     else
                       ["à vérifier", "bg-amber-50 text-amber-800 ring-amber-200"]
                     end
    tag.span(label, class: "ml-1 inline-flex rounded-full px-1.5 text-[11px] ring-1 #{classes}",
                    title: field["confidence"] ? "Confiance de Jev : #{(field['confidence'].to_f * 100).round} %" : "Trouvé dans le document")
  end

  # « Facture · Proximus · 84,12 € » — la ligne qui permet de trier sans ouvrir.
  def mail_attachment_summary(attachment, third_parties)
    parts = [MailAttachment::KIND_LABELS[attachment.kind] || (attachment.pdf? ? "PDF" : "Image")]
    supplier = third_parties[attachment.proposed(:third_party_id)]
    parts << supplier.name if supplier
    parts << number_to_currency(attachment.proposed(:total_cents) / 100.0) if attachment.proposed(:total_cents)
    parts.join(" · ")
  end
end
