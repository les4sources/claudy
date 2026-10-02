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
#  embedded_in_id      :bigint
#  mail_message_id     :bigint           not null
#  purchase_invoice_id :bigint
#
# Indexes
#
#  index_mail_attachments_on_embedded_in_id       (embedded_in_id)
#  index_mail_attachments_on_mail_message_id      (mail_message_id)
#  index_mail_attachments_on_purchase_invoice_id  (purchase_invoice_id)
#  index_mail_attachments_on_sha256               (sha256)
#
# Foreign Keys
#
#  fk_rails_...  (embedded_in_id => mail_attachments.id)
#  fk_rails_...  (mail_message_id => mail_messages.id)
#  fk_rails_...  (purchase_invoice_id => purchase_invoices.id)
#
class MailAttachment < ApplicationRecord
  KIND_LABELS = {
    "invoice" => "Facture",
    "credit_note" => "Note de crédit",
    "reminder" => "Rappel",
    "other" => "Autre document",
    "sales" => "Facture de vente (émise par nous)",
    "ubl_data" => "Facture électronique (UBL)"
  }.freeze

  belongs_to :mail_message
  belongs_to :purchase_invoice, optional: true
  # Le PDF embarqué dans une facture électronique pointe vers son XML UBL.
  belongs_to :embedded_in, class_name: "MailAttachment", optional: true
  has_many :embedded, class_name: "MailAttachment", foreign_key: :embedded_in_id, dependent: :nullify
  has_one_attached :file

  validates :filename, :content_type, :sha256, presence: true

  def pdf? = content_type == "application/pdf"

  def ubl? = content_type == "application/xml"

  def kind = proposal.dig("kind", "value")

  # Sans avis de Jev, un PDF est présumé facture : mieux vaut une pièce de trop
  # dans la file qu'une facture qui s'en échappe. Un XML UBL ne l'est que s'il
  # n'embarque pas de PDF — sinon c'est le PDF qui porte la facture.
  def invoice_like?
    return %w[invoice credit_note].include?(kind) if ubl?

    pdf? && (kind.nil? || %w[invoice credit_note].include?(kind))
  end

  # Les valeurs viennent de la facture électronique : exactes, pas devinées.
  def from_ubl? = proposal.dig("kind", "source") == "ubl"

  def proposed(field) = proposal.dig(field.to_s, "value")

  # De quoi pré-remplir « Nouveau fournisseur » quand aucun tiers connu ne
  # correspond : ce que la lecture de la pièce a trouvé, à relire.
  def supplier_draft
    { name: proposed(:supplier_name), vat_number: proposed(:supplier_vat), iban: proposed(:supplier_iban) }
  end

  # La facture déjà encodée pour cette pièce : par le fichier lui-même, ou par
  # le numéro chez le même fournisseur. Le second cas rattrape les deux mails
  # qu'OkiOki envoie pour une même facture (le PDF, puis l'UBL), dont les
  # fichiers diffèrent.
  def existing_invoice
    purchase_invoice || PurchaseInvoice.find_by(pdf_sha256: sha256) || invoice_with_same_reference
  end

  def invoice_with_same_reference
    number = proposed(:number)
    return nil if number.blank?

    suppliers = [proposed(:third_party_id)].compact
    vat = MailIntake::InvoiceCandidates.normalize_vat(proposed(:supplier_vat))
    if vat
      suppliers += ThirdParty.where.not(vat_number: [nil, ""])
                             .select { |t| MailIntake::InvoiceCandidates.normalize_vat(t.vat_number) == vat }.map(&:id)
    end
    same_supplier = suppliers.any? ? PurchaseInvoice.find_by(number: number, third_party_id: suppliers.uniq) : nil
    same_supplier || invoice_with_same_number_amount_and_date(number)
  end

  # Quand la lecture du PDF n'a pas reconnu le fournisseur (ou a retenu un
  # autre numéro de TVA que celui de l'UBL, vu sur la facture de Delphine
  # Guillaume), le numéro, le total ET la date ensemble désignent encore la
  # même facture : trois coïncidences d'un coup ne sont pas une coïncidence.
  def invoice_with_same_number_amount_and_date(number)
    total = proposed(:total_cents)
    issued_on = proposed(:issued_on)
    return nil if total.blank? || issued_on.blank?

    PurchaseInvoice.find_by(number: number, total_cents: total, issued_on: issued_on)
  end
end
