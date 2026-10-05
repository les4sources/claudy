# Serveur MCP de Claudy : ce que Claude peut faire dans Claudy quand on l'y
# connecte comme connecteur (Michael, 2026-10-05). Les modèles de ce module
# sont le serveur OAuth qui l'authentifie ; les outils vivent dans
# `app/services/mcp/`.
module Mcp
  SCOPE = "claudy".freeze

  def self.table_name_prefix = "mcp_"

  # Empreinte d'un secret (code, jeton). On ne garde jamais le secret lui-même.
  def self.digest(secret) = Digest::SHA256.hexdigest(secret.to_s)

  # Les comptes Claudy autorisés à brancher Claude, par adresse e-mail
  # (`MCP_ALLOWED_EMAILS`, séparées par des virgules). Vide = personne : un
  # outil qui écrit dans les comptes des familles n'est pas ouvert par défaut.
  def self.allowed?(user)
    return false if user.nil? || user.member_deactivated?

    allowed = ENV.fetch("MCP_ALLOWED_EMAILS", "").split(",").map { |email| email.strip.downcase }
    allowed.include?(user.email.to_s.downcase)
  end

  # L'adresse publique de Claudy, telle que Claude la voit. Derrière le proxy
  # de Hatchbox, la requête arrive parfois en http : en production on force
  # https, sinon les métadonnées OAuth annonceraient une adresse que Claude
  # refuse. `MCP_BASE_URL` reste là pour le cas où l'hôte changerait.
  def self.base_url(request)
    return ENV["MCP_BASE_URL"].chomp("/") if ENV["MCP_BASE_URL"].present?
    return "https://#{request.host}" if Rails.env.production?

    request.base_url
  end
end
