# Une pièce jointe d'un mail — le PDF qui deviendra peut-être une facture.
#
# `proposal` porte ce que le code et Jev en ont tiré. Chaque champ a la forme
# `{ "value" => …, "source" => "code" | "jev", "confidence" => 0..1 }` : la
# source compte, un numéro de TVA reconnu par le code ne se discute pas, une
# date choisie par Jev à 0,55 se relit.
# == Schema Information
#
# Table name: mail_attachments
#
#  id                  :bigint           not null, primary key
#  content_type        :string           not null
#  filename            :string           not null
#  proposal            :jsonb            not null
#  sha256              :string           not null
#  text_content        :text
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#  mail_message_id     :bigint           not null
#  purchase_invoice_id :bigint
#
# Indexes
#
#  index_mail_attachments_on_mail_message_id      (mail_message_id)
#  index_mail_attachments_on_purchase_invoice_id  (purchase_invoice_id)
#  index_mail_attachments_on_sha256               (sha256)
#
# Foreign Keys
#
#  fk_rails_...  (mail_message_id => mail_messages.id)
#  fk_rails_...  (purchase_invoice_id => purchase_invoices.id)
#
class MailAttachment < ApplicationRecord
  KIND_LABELS = {
    "invoice" => "Facture",
    "credit_note" => "Note de crédit",
    "reminder" => "Rappel",
    "other" => "Autre document"
  }.freeze

  belongs_to :mail_message
  belongs_to :purchase_invoice, optional: true
  has_one_attached :file

  validates :filename, :content_type, :sha256, presence: true

  def pdf? = content_type == "application/pdf"

  def kind = proposal.dig("kind", "value")

  # Sans avis de Jev, un PDF est présumé facture : mieux vaut une pièce de trop
  # dans la file qu'une facture qui s'en échappe.
  def invoice_like? = pdf? && (kind.nil? || %w[invoice credit_note].include?(kind))

  def proposed(field) = proposal.dig(field.to_s, "value")

  # La facture déjà encodée avec exactement ce fichier, s'il y en a une.
  def existing_invoice
    purchase_invoice || PurchaseInvoice.find_by(pdf_sha256: sha256)
  end
end
