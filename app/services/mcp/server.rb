module Mcp
  # Le protocole MCP réduit à ce dont Claudy a besoin : la poignée de main
  # (`initialize`), `ping`, et des outils (`tools/list`, `tools/call`). Pas de
  # ressources ni de prompts — tout passe par des outils métier, jamais par du
  # code arbitraire.
  class Server
    PROTOCOL_VERSIONS = %w[2025-11-25 2025-06-18 2025-03-26 2024-11-05].freeze

    TOOLS = [
      Tools::ChercherComptes,
      Tools::DiagnosticCompte,
      Tools::LignesCompte,
      Tools::PosteParMois,
      Tools::VirementsRecus,
      Tools::HistoriqueLigne,
      Tools::SupprimerLignes,
      Tools::ContrePasserLignes,
      Tools::PasserEcriture,
      Tools::AbandonnerDette,
      Tools::EncoderReglement
    ].freeze

    INSTRUCTIONS = <<~TEXT.freeze
      Claudy est l'app de gestion des 4 Sources (tiers-lieu à Yvoir). Ces outils
      lisent et corrigent les comptes courants des familles et des personnes
      (codes SRC-0001, SRC-0002…).

      Le grand livre : chaque ligne a un montant SIGNÉ (positif = dû par le
      compte, négatif = règlement ou avoir) et un POSTE (bar, épicerie, repas,
      cagnotte, dôme, animaux, charges, divers). Le solde n'est jamais stocké.
      Ce qui reste dû se lit poste par poste : un règlement n'éteint que les
      dettes de son poste, les plus anciennes d'abord, sauf s'il nomme son mois
      (référence « reprise-bar:2026-05 »).

      Pour diagnostiquer, commence par diagnostic_compte, puis lignes_compte ou
      poste_par_mois. Les outils d'écriture rendent d'abord un APERÇU et un code
      de confirmation, sans rien écrire. Montre l'aperçu à l'utilisateur et ne
      rappelle l'outil avec `confirmation` qu'après son accord explicite. Une
      ligne rattachée à un décompte émis est verrouillée : on la contre-passe,
      on ne la supprime pas. Tout est tracé dans l'historique (PaperTrail).
    TEXT

    def self.error_response(id, code, message)
      { jsonrpc: "2.0", id: id, error: { code: code, message: message } }
    end

    def initialize(user:)
      @user = user
    end

    # Un message ou un lot de messages. Rend nil quand il n'y a rien à
    # répondre (notifications seules).
    def handle(payload)
      if payload.is_a?(Array)
        replies = payload.filter_map { |message| handle_one(message) }
        replies.presence
      else
        handle_one(payload)
      end
    end

    private

    def handle_one(message)
      return self.class.error_response(nil, -32_600, "Requête invalide") unless message.is_a?(Hash)
      # Notification, ou réponse du client à une requête : rien à rendre.
      return nil unless message.key?("id") && message["method"].present?

      id = message["id"]
      params = message["params"].is_a?(Hash) ? message["params"] : {}

      case message["method"]
      when "initialize" then result(id, initialize_result(params))
      when "ping" then result(id, {})
      when "tools/list" then result(id, { tools: TOOLS.map(&:definition) })
      when "tools/call" then call_tool(id, params)
      else self.class.error_response(id, -32_601, "Méthode inconnue : #{message['method']}")
      end
    end

    def initialize_result(params)
      asked = params["protocolVersion"].to_s
      {
        protocolVersion: PROTOCOL_VERSIONS.include?(asked) ? asked : PROTOCOL_VERSIONS.first,
        capabilities: { tools: { listChanged: false } },
        serverInfo: { name: "claudy", title: "Claudy", version: "1.0.0" },
        instructions: INSTRUCTIONS
      }
    end

    def call_tool(id, params)
      tool = TOOLS.find { |candidate| candidate.tool_name == params["name"] }
      return self.class.error_response(id, -32_602, "Outil inconnu : #{params['name']}") if tool.nil?

      arguments = params["arguments"].is_a?(Hash) ? params["arguments"] : {}
      text = tool.new(user: @user).call(arguments)
      result(id, { content: [{ type: "text", text: text }], isError: false })
    rescue Tools::Base::Error, ActiveRecord::RecordInvalid, AccountEntry::Locked,
           Finance::RecordSettlement::VentilationMismatch => e
      result(id, { content: [{ type: "text", text: e.message }], isError: true })
    rescue StandardError => e
      Sentry.capture_exception(e)
      Rails.logger.error("[MCP] #{params['name']} : #{e.class} #{e.message}")
      result(id, { content: [{ type: "text", text: "Erreur interne de Claudy (#{e.class}) : #{e.message}" }], isError: true })
    end

    def result(id, value)
      { jsonrpc: "2.0", id: id, result: value }
    end
  end
end
