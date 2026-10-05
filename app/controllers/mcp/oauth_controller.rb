module Mcp
  # Le serveur d'autorisation OAuth 2.1 que claude.ai attend d'un connecteur :
  # métadonnées de découverte (RFC 9728 et 8414), enregistrement dynamique des
  # clients (RFC 7591) et échange de jetons, PKCE obligatoire. La page où un
  # humain dit oui est dans `AuthorizationsController`.
  #
  # Pas de cookie ici, que des appels de machine à machine : la protection CSRF
  # n'a rien à protéger.
  class OauthController < ActionController::Base
    skip_forgery_protection
    layout false

    rate_limit to: 20, within: 1.minute, only: %i[register token],
               with: -> { render json: { error: "slow_down" }, status: :too_many_requests }

    # RFC 9728 : où trouver le serveur d'autorisation de la ressource /mcp.
    def protected_resource
      render json: {
        resource: "#{base_url}/mcp",
        authorization_servers: [base_url],
        bearer_methods_supported: ["header"],
        scopes_supported: [Mcp::SCOPE],
        resource_name: "Claudy"
      }
    end

    # RFC 8414.
    def authorization_server
      render json: {
        issuer: base_url,
        authorization_endpoint: "#{base_url}/oauth/authorize",
        token_endpoint: "#{base_url}/oauth/token",
        registration_endpoint: "#{base_url}/oauth/register",
        scopes_supported: [Mcp::SCOPE],
        response_types_supported: ["code"],
        grant_types_supported: %w[authorization_code refresh_token],
        code_challenge_methods_supported: ["S256"],
        token_endpoint_auth_methods_supported: ["none"]
      }
    end

    # RFC 7591. Un client public : pas de secret, c'est PKCE qui protège
    # l'échange. S'enregistrer ne donne aucun accès.
    def register
      body = json_body
      client = Mcp::Client.new(name: body["client_name"].to_s.first(100).presence,
                               redirect_uris: Array(body["redirect_uris"]).map(&:to_s))
      unless client.save
        return render json: { error: "invalid_redirect_uri", error_description: client.errors.full_messages.to_sentence },
                      status: :bad_request
      end

      render status: :created, json: {
        client_id: client.client_id,
        client_id_issued_at: client.created_at.to_i,
        client_name: client.name,
        redirect_uris: client.redirect_uris,
        grant_types: %w[authorization_code refresh_token],
        response_types: ["code"],
        token_endpoint_auth_method: "none"
      }
    end

    def token
      response.headers["Cache-Control"] = "no-store"
      client = Mcp::Client.find_by(client_id: params[:client_id].to_s)
      return oauth_error("invalid_client", :unauthorized) if client.nil?

      case params[:grant_type]
      when "authorization_code"
        grant = Mcp::Grant.transaction do
          Mcp::Grant.redeem(code: params[:code].to_s, client: client,
                            code_verifier: params[:code_verifier].to_s, redirect_uri: params[:redirect_uri].to_s)
        end
        return oauth_error("invalid_grant") if grant.nil? || !Mcp.allowed?(grant.user)

        render json: Mcp::Token.issue!(client: client, user: grant.user).merge(scope: Mcp::SCOPE)
      when "refresh_token"
        tokens = Mcp::Token.refresh!(refresh: params[:refresh_token].to_s, client: client)
        return oauth_error("invalid_grant") if tokens.nil?

        render json: tokens.merge(scope: Mcp::SCOPE)
      else
        oauth_error("unsupported_grant_type")
      end
    end

    private

    def base_url = Mcp.base_url(request)

    def json_body
      JSON.parse(request.raw_post.presence || "{}")
    rescue JSON::ParserError
      {}
    end

    def oauth_error(code, status = :bad_request)
      render json: { error: code }, status: status
    end
  end
end
