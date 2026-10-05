module Mcp
  # Le point d'entrée MCP (transport « Streamable HTTP », sans état) : Claude
  # POSTe un message JSON-RPC, Claudy répond en JSON. Pas de flux SSE ni de
  # session : chaque appel porte son jeton et se suffit à lui-même.
  #
  # Sans jeton valide, la réponse 401 dit à Claude où trouver le serveur
  # d'autorisation (RFC 9728) — c'est ce qui déclenche la connexion OAuth.
  class ServerController < ActionController::Base
    skip_forgery_protection
    layout false

    before_action :authenticate_token!, only: :handle

    def handle
      payload = JSON.parse(request.raw_post)
      reply = Mcp::Server.new(user: @token.user).handle(payload)
      reply.nil? ? head(:accepted) : render(json: reply)
    rescue JSON::ParserError
      render json: Mcp::Server.error_response(nil, -32_700, "JSON invalide"), status: :bad_request
    end

    # Pas de flux serveur → client ni de session à fermer.
    def unsupported
      response.headers["Allow"] = "POST"
      head :method_not_allowed
    end

    private

    def authenticate_token!
      @token = Mcp::Token.authenticate(request.authorization.to_s[/\ABearer\s+(.+)\z/i, 1])
      return if @token

      metadata = "#{Mcp.base_url(request)}/.well-known/oauth-protected-resource"
      response.headers["WWW-Authenticate"] = %(Bearer resource_metadata="#{metadata}", scope="#{Mcp::SCOPE}")
      render json: { error: "unauthorized" }, status: :unauthorized
    end
  end
end
