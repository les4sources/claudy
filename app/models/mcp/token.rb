# Un jeton d'accès et son jeton de rafraîchissement. L'accès vaut une heure ;
# le rafraîchissement trente jours, et il TOURNE : chaque usage révoque
# l'ancien couple et en émet un neuf. Révoquer une ligne coupe Claude net.
# == Schema Information
#
# Table name: mcp_tokens
#
#  id                 :bigint           not null, primary key
#  access_digest      :string           not null
#  access_expires_at  :datetime         not null
#  last_used_at       :datetime
#  refresh_digest     :string           not null
#  refresh_expires_at :datetime         not null
#  revoked_at         :datetime
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#  mcp_client_id      :bigint           not null
#  user_id            :bigint           not null
#
# Indexes
#
#  index_mcp_tokens_on_access_digest   (access_digest) UNIQUE
#  index_mcp_tokens_on_mcp_client_id   (mcp_client_id)
#  index_mcp_tokens_on_refresh_digest  (refresh_digest) UNIQUE
#  index_mcp_tokens_on_user_id         (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (mcp_client_id => mcp_clients.id)
#  fk_rails_...  (user_id => users.id)
#
class Mcp::Token < ApplicationRecord
  ACCESS_TTL = 1.hour
  REFRESH_TTL = 30.days

  belongs_to :client, class_name: "Mcp::Client", foreign_key: :mcp_client_id
  belongs_to :user

  scope :live, -> { where(revoked_at: nil) }

  # Rend `{ access_token:, refresh_token:, expires_in: }` — les secrets en clair
  # ne sortent qu'ici, une fois.
  def self.issue!(client:, user:)
    access = SecureRandom.urlsafe_base64(32)
    refresh = SecureRandom.urlsafe_base64(32)
    create!(client: client, user: user,
            access_digest: Mcp.digest(access), refresh_digest: Mcp.digest(refresh),
            access_expires_at: ACCESS_TTL.from_now, refresh_expires_at: REFRESH_TTL.from_now)
    { access_token: access, token_type: "Bearer", expires_in: ACCESS_TTL.to_i, refresh_token: refresh }
  end

  # L'utilisateur derrière un jeton d'accès valide, ou nil. Un compte retiré de
  # `MCP_ALLOWED_EMAILS` ou désactivé perd l'accès sur-le-champ.
  def self.authenticate(access)
    return nil if access.blank?

    token = live.find_by(access_digest: Mcp.digest(access))
    return nil if token.nil? || token.access_expires_at.past? || !Mcp.allowed?(token.user)

    token.update_column(:last_used_at, Time.current) if token.last_used_at.nil? || token.last_used_at < 1.minute.ago
    token
  end

  def self.refresh!(refresh:, client:)
    transaction do
      token = live.lock.find_by(refresh_digest: Mcp.digest(refresh), mcp_client_id: client.id)
      return nil if token.nil? || token.refresh_expires_at.past? || !Mcp.allowed?(token.user)

      token.update!(revoked_at: Time.current)
      issue!(client: client, user: token.user)
    end
  end
end
