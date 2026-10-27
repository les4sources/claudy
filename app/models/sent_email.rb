# == Schema Information
#
# Table name: sent_emails
#
#  id                    :bigint           not null, primary key
#  body_html             :text
#  body_text             :text
#  delivery_issue        :string
#  delivery_issue_at     :datetime
#  delivery_issue_detail :string
#  mailer                :string
#  sent_at               :datetime         not null
#  source                :string           default("app"), not null
#  subject               :string
#  tag                   :string
#  to_email              :citext           not null
#  created_at            :datetime         not null
#  updated_at            :datetime         not null
#  customer_id           :bigint           not null
#  postmark_message_id   :string
#  ses_message_id        :string
#
# Indexes
#
#  index_sent_emails_on_customer_id              (customer_id)
#  index_sent_emails_on_customer_id_and_sent_at  (customer_id,sent_at)
#  index_sent_emails_on_postmark_message_id      (postmark_message_id) UNIQUE WHERE (postmark_message_id IS NOT NULL)
#  index_sent_emails_on_ses_message_id           (ses_message_id) WHERE (ses_message_id IS NOT NULL)
#
# Foreign Keys
#
#  fk_rails_...  (customer_id => customers.id)
#
# Journal des emails envoyés à un client. Alimenté à deux endroits, et
# uniquement pour les emails dont le client est DESTINATAIRE (`to`) : les
# notifications internes (AdminMailer, animateurs) et le bcc d'archivage
# n'entrent jamais ici.
#
#   1. `SentEmails::Observer` — à chaque livraison réelle d'ActionMailer ;
#   2. `rails sent_emails:backfill` — rapatriement de l'historique Postmark
#      (rétention de contenu ~45 jours côté Postmark).
#
# Le dédoublonnage entre les deux sources repose sur `postmark_message_id`.
#
# Envoyé par Amazon SES, l'email garde son `ses_message_id` : quand SES
# signale un rebond ou une plainte (`SentEmails::SesFeedback`), la ligne porte
# le problème de remise (`delivery_issue`), visible sur la fiche client.
class SentEmail < ApplicationRecord
  SOURCES = %w[app postmark].freeze
  # bounce = adresse refusée pour de bon, soft_bounce = refus temporaire que
  # SES n'a pas réussi à contourner, complaint = marqué comme spam.
  DELIVERY_ISSUES = %w[bounce soft_bounce complaint].freeze

  belongs_to :customer

  validates :to_email, presence: true
  validates :sent_at, presence: true
  validates :source, inclusion: { in: SOURCES }
  validates :delivery_issue, inclusion: { in: DELIVERY_ISSUES }, allow_nil: true

  scope :recent, -> { order(sent_at: :desc, id: :desc) }

  def display_subject
    subject.presence || "(sans sujet)"
  end

  # Corps affichable dans la modale. On privilégie la version HTML (c'est ce que
  # le client a reçu) ; sinon on remonte le texte brut, échappé et converti en
  # HTML minimal par l'appelant.
  def html_body?
    body_html.present?
  end
end
