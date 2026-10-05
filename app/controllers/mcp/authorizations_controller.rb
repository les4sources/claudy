module Mcp
  # La page où un humain autorise Claude à agir dans Claudy en son nom.
  #
  # Il faut être connecté (Devise ramène ici après la connexion) ET figurer dans
  # `MCP_ALLOWED_EMAILS`. Tout ce que Claude fera ensuite sera signé de ce
  # compte dans l'historique PaperTrail.
  class AuthorizationsController < ActionController::Base
    layout "devise"

    OAUTH_PARAMS = %i[response_type client_id redirect_uri code_challenge code_challenge_method state scope resource].freeze

    before_action :authenticate_user!
    before_action :load_request

    def new
      return render :forbidden, status: :forbidden unless Mcp.allowed?(current_user)
    end

    def create
      return render :forbidden, status: :forbidden unless Mcp.allowed?(current_user)
      return redirect_back_to_client(error: "access_denied") unless params[:decision] == "allow"

      code = Mcp::Grant.issue!(client: @client, user: current_user,
                               code_challenge: @oauth[:code_challenge], redirect_uri: @oauth[:redirect_uri])
      redirect_back_to_client(code: code)
    end

    private

    # Un client inconnu ou une adresse de retour qui n'est pas la sienne : on
    # n'y renvoie RIEN, on affiche l'erreur ici. Le reste des erreurs repart
    # chez le client, comme le veut OAuth.
    def load_request
      @oauth = params.slice(*OAUTH_PARAMS).permit(*OAUTH_PARAMS).to_h.symbolize_keys
      @client = Mcp::Client.find_by(client_id: @oauth[:client_id].to_s)
      unless @client && @client.redirect_uris.include?(@oauth[:redirect_uri])
        return render :invalid, status: :bad_request
      end

      return redirect_back_to_client(error: "unsupported_response_type") unless @oauth[:response_type] == "code"
      return if @oauth[:code_challenge].present? && @oauth[:code_challenge_method] == "S256"

      redirect_back_to_client(error: "invalid_request")
    end

    def redirect_back_to_client(**values)
      uri = URI.parse(@oauth[:redirect_uri])
      query = URI.decode_www_form(uri.query.to_s) + values.merge(state: @oauth[:state]).compact.map { |k, v| [k.to_s, v] }
      uri.query = URI.encode_www_form(query)
      redirect_to uri.to_s, allow_other_host: true
    end
  end
end
