# Un code d'autorisation : ce que Claudy rend à Claude quand un humain a dit
# oui. Valable dix minutes, une seule fois, et lié au défi PKCE que Claude a
# présenté : un code intercepté ne sert à rien sans le vérificateur.
# == Schema Information
#
# Table name: mcp_grants
#
#  id             :bigint           not null, primary key
#  code_challenge :string           not null
#  code_digest    :string           not null
#  expires_at     :datetime         not null
#  redirect_uri   :string           not null
#  used_at        :datetime
#  created_at     :datetime         not null
#  updated_at     :datetime         not null
#  mcp_client_id  :bigint           not null
#  user_id        :bigint           not null
#
# Indexes
#
#  index_mcp_grants_on_code_digest    (code_digest) UNIQUE
#  index_mcp_grants_on_mcp_client_id  (mcp_client_id)
#  index_mcp_grants_on_user_id        (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (mcp_client_id => mcp_clients.id)
#  fk_rails_...  (user_id => users.id)
#
class Mcp::Grant < ApplicationRecord
  TTL = 10.minutes

  belongs_to :client, class_name: "Mcp::Client", foreign_key: :mcp_client_id
  belongs_to :user

  # Crée le code et rend le secret en clair — la seule fois où il existe.
  def self.issue!(client:, user:, code_challenge:, redirect_uri:)
    code = SecureRandom.urlsafe_base64(32)
    create!(client: client, user: user, code_digest: Mcp.digest(code), code_challenge: code_challenge,
            redirect_uri: redirect_uri, expires_at: TTL.from_now)
    code
  end

  # Échange le code contre l'utilisateur, ou rend nil. Le code est brûlé dès
  # qu'il est présenté, même si la suite échoue : un code rejoué est suspect.
  def self.redeem(code:, client:, code_verifier:, redirect_uri:)
    grant = lock.find_by(code_digest: Mcp.digest(code), mcp_client_id: client.id)
    return nil if grant.nil? || grant.used_at.present?

    grant.update!(used_at: Time.current)
    return nil if grant.expires_at.past? || grant.redirect_uri != redirect_uri
    return nil unless grant.pkce_valid?(code_verifier)

    grant
  end

  def pkce_valid?(verifier)
    return false if verifier.blank?

    expected = Base64.urlsafe_encode64(Digest::SHA256.digest(verifier), padding: false)
    ActiveSupport::SecurityUtils.secure_compare(expected, code_challenge)
  end
end
