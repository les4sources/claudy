# Une boîte mail que Claudy lit (messagerie, phase 1). Elle reste sur
# Mail-in-a-Box : Claudy n'en est qu'un lecteur de plus, à côté de Roundcube et
# des téléphones. Le mot de passe vit dans l'ENV, jamais en base — voir
# `#password`.
# == Schema Information
#
# Table name: mail_accounts
#
#  id             :bigint           not null, primary key
#  active         :boolean          default(TRUE), not null
#  address        :string           not null
#  folder         :string           default("INBOX"), not null
#  imap_host      :string           default("box.les4sources.be"), not null
#  last_error     :text
#  last_synced_at :datetime
#  last_uid       :bigint           default(0), not null
#  purpose        :string           not null
#  uid_validity   :bigint
#  created_at     :datetime         not null
#  updated_at     :datetime         not null
#
# Indexes
#
#  index_mail_accounts_on_address  (address) UNIQUE
#
class MailAccount < ApplicationRecord
  PURPOSES = %w[accounting].freeze

  has_many :mail_messages, dependent: :restrict_with_error

  validates :address, presence: true, uniqueness: true
  validates :purpose, inclusion: { in: PURPOSES }

  scope :actives, -> { where(active: true) }

  # `compta@les4sources.be` → `MAIL_PASSWORD_COMPTA`.
  def password_env_key = "MAIL_PASSWORD_#{address.split('@').first.upcase.gsub(/[^A-Z0-9]/, '_')}"

  def password = ENV[password_env_key].presence

  def imap_username = address
end
