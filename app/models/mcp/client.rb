# Un client OAuth enregistré : claude.ai, Claude Code… Il s'enregistre seul
# (enregistrement dynamique, RFC 7591), ce qui ne lui donne AUCUN accès : il
# faut encore qu'un humain autorisé se connecte à Claudy et accepte.
#
# Les adresses de retour sont limitées à Claude et à la machine locale (Claude
# Code). Sans cette liste, n'importe quel site pourrait se faire enregistrer
# et récolter un code d'autorisation sur un clic distrait.
# == Schema Information
#
# Table name: mcp_clients
#
#  id            :bigint           not null, primary key
#  name          :string
#  redirect_uris :string           default([]), not null, is an Array
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#  client_id     :string           not null
#
# Indexes
#
#  index_mcp_clients_on_client_id  (client_id) UNIQUE
#
class Mcp::Client < ApplicationRecord
  ALLOWED_REDIRECT = [
    %r{\Ahttps://claude\.ai/},
    %r{\Ahttps://claude\.com/},
    %r{\Ahttp://localhost(:\d+)?/},
    %r{\Ahttp://127\.0\.0\.1(:\d+)?/}
  ].freeze

  has_many :grants, class_name: "Mcp::Grant", foreign_key: :mcp_client_id, dependent: :destroy
  has_many :tokens, class_name: "Mcp::Token", foreign_key: :mcp_client_id, dependent: :destroy

  validates :client_id, presence: true, uniqueness: true
  validate :redirect_uris_allowed

  before_validation { self.client_id ||= SecureRandom.uuid }

  def self.allowed_redirect?(uri)
    ALLOWED_REDIRECT.any? { |pattern| pattern.match?(uri.to_s) }
  end

  def display_name = name.presence || "Client sans nom"

  private

  def redirect_uris_allowed
    errors.add(:redirect_uris, "est vide") if redirect_uris.blank?
    refusees = redirect_uris.to_a.reject { |uri| self.class.allowed_redirect?(uri) }
    errors.add(:redirect_uris, "non autorisée : #{refusees.join(', ')}") if refusees.any?
  end
end
