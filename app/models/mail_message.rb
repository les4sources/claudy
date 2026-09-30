# Un mail arrivé dans une boîte lue par Claudy (messagerie, phase 1).
#
# Il n'est jamais supprimé : « ignorer » le sort de la file et garde qui l'a
# décidé. Le brut (`raw`, le .eml) est gardé tel quel — c'est lui qu'on relira
# le jour où une extraction se trompe.
# == Schema Information
#
# Table name: mail_messages
#
#  id              :bigint           not null, primary key
#  analyzed_at     :datetime
#  body_text       :text
#  from_address    :string
#  from_name       :string
#  handled_at      :datetime
#  imap_uid        :bigint
#  received_at     :datetime         not null
#  status          :string           default("pending"), not null
#  subject         :string
#  triage          :jsonb            not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  handled_by_id   :bigint
#  mail_account_id :bigint           not null
#  message_id      :string           not null
#
# Indexes
#
#  index_mail_messages_on_handled_by_id                   (handled_by_id)
#  index_mail_messages_on_mail_account_id                 (mail_account_id)
#  index_mail_messages_on_mail_account_id_and_message_id  (mail_account_id,message_id) UNIQUE
#  index_mail_messages_on_status_and_received_at          (status,received_at)
#
# Foreign Keys
#
#  fk_rails_...  (handled_by_id => users.id)
#  fk_rails_...  (mail_account_id => mail_accounts.id)
#
class MailMessage < ApplicationRecord
  STATUSES = %w[pending filed ignored].freeze
  STATUS_LABELS = { "pending" => "À traiter", "filed" => "Classé", "ignored" => "Ignoré" }.freeze

  belongs_to :mail_account
  belongs_to :handled_by, class_name: "User", optional: true
  has_many :mail_attachments, -> { order(:id) }, dependent: :destroy
  has_one_attached :raw

  validates :message_id, presence: true, uniqueness: { scope: :mail_account_id }
  validates :status, inclusion: { in: STATUSES }

  scope :pending, -> { where(status: "pending") }
  scope :recent_first, -> { order(received_at: :desc, id: :desc) }
  scope :to_analyze, -> { where(analyzed_at: nil) }

  def pending? = status == "pending"

  def sender_label = from_name.presence || from_address

  def ignore!(user)
    update!(status: "ignored", handled_by: user, handled_at: Time.current)
  end

  def restore!
    update!(status: "pending", handled_by: nil, handled_at: nil)
  end

  # Classé dès que chaque pièce qui ressemble à une facture a la sienne : les
  # conditions générales jointes ne doivent pas garder un mail dans la file.
  def settle_if_complete!(user)
    invoices = mail_attachments.select(&:invoice_like?)
    return if invoices.empty? || invoices.any? { |a| a.purchase_invoice_id.nil? }

    update!(status: "filed", handled_by: user, handled_at: Time.current)
  end
end
