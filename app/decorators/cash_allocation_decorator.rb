# L'affichage d'une part de ligne de trésorerie.
class CashAllocationDecorator < ApplicationDecorator
  delegate_all

  # Ce que la part rapproche, en mots : sur l'écran de ventilation, c'est ce
  # qui dit qu'une part ne se retire pas à la légère.
  DOCUMENTS = {
    "PurchaseInvoice" => "la facture d'achat",
    "SalesInvoice" => "la facture de vente",
    "ExpenseReport" => "la note de frais",
    "Stay" => "le séjour",
    "Event" => "l'événement",
    "MemberAccount" => "le compte de l'habitant",
    "StripePayout" => "le versement Stripe",
    "CarrierStatement" => "le relevé du porteur",
    "ConsignmentReport" => "le relevé de dépôt-vente",
    "EventSettlementLine" => "le règlement de l'événement"
  }.freeze

  def document_label
    return if object.document_type.blank?

    "#{DOCUMENTS.fetch(object.document_type, object.document_type)} ##{object.document_id}"
  end
end
