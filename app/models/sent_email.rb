# == Schema Information
#
# Table name: sent_emails
#
#  id                  :bigint           not null, primary key
#  customer_id         :bigint           not null
#  to_email            :citext           not null
#  subject             :string
#  body_html           :text
#  body_text           :text
#  mailer              :string
#  tag                 :string
#  postmark_message_id :string
#  sent_at             :datetime         not null
#  source              :string           default("app"), not null
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
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
class SentEmail < ApplicationRecord
  SOURCES = %w[app postmark].freeze

  belongs_to :customer

  validates :to_email, presence: true
  validates :sent_at, presence: true
  validates :source, inclusion: { in: SOURCES }

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
