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
      Tools::EncoderReglement,
      Tools::Sejours::ChercherSejours,
      Tools::Sejours::FicheSejour,
      Tools::Sejours::Disponibilites,
      Tools::Sejours::DevisSejour,
      Tools::Sejours::ChercherClients,
      Tools::Sejours::FicheClient,
      Tools::Sejours::CreerSejour,
      Tools::Sejours::ModifierSejour,
      Tools::Sejours::ChangerStatutSejour,
      Tools::Sejours::PreconfirmerSejour,
      Tools::Sejours::RefuserSejour,
      Tools::Sejours::RenvoyerConfirmation,
      Tools::Sejours::TraiterDemandeModification,
      Tools::Sejours::NoterSejour,
      Tools::Sejours::EnregistrerPaiementSejour,
      Tools::Sejours::ModifierPaiementSejour,
      Tools::Sejours::SupprimerSejour,
      Tools::Sejours::ModifierClient,
      Tools::Activites::ChercherActivites,
      Tools::Activites::FicheActivite,
      Tools::Activites::ReservationsActivites,
      Tools::Activites::AjouterActiviteSejour,
      Tools::Activites::ModifierReservationActivite,
      Tools::Activites::AnnulerReservationActivite,
      Tools::Activites::ValiderReservationActivite,
      Tools::Activites::RefuserReservationActivite,
      Tools::Activites::DeclarerTenue,
      Tools::Activites::CreerCreneau,
      Tools::Activites::SupprimerCreneau,
      Tools::Activites::EnregistrerActivite,
      Tools::Activites::PublierActivite
    ].freeze

    INSTRUCTIONS = <<~TEXT.freeze
      Claudy est l'app de gestion des 4 Sources (tiers-lieu à Yvoir, Domaine
      d'Ahinvaux). Ces outils font ce que fait l'interface, domaine par domaine.

      SÉJOURS. Un séjour (#1234) rattache un client à une composition : gîte ou
      chambres, espaces, camping, repas, activités, draps. Statuts : en attente
      (pending), pré-confirmé (acompte demandé, bloque le calendrier), confirmé,
      annulé. Pour trouver un séjour : chercher_sejours, puis fiche_sejour. Avant
      d'en créer un : chercher_clients (pas de doublon de client), disponibilites
      et devis_sejour. Plusieurs outils ÉCRIVENT AU CLIENT (confirmation,
      pré-confirmation, refus, demande de modification) : leur aperçu le dit,
      dis-le aussi à l'utilisateur avant qu'il accepte.

      ACTIVITÉS. Une activité (#12, balade avec les ânes…) a un porteur et des
      créneaux (#345) ; un séjour s'y inscrit par une réservation (#678), « à
      valider » par le porteur puis confirmée. Après le créneau, on déclare sa
      tenue (a eu lieu / n'a pas eu lieu), ce qui ouvre la rémunération du
      porteur. File de travail : reservations_activites.

      COMPTES COURANTS des familles et des personnes (SRC-0001…). Le grand
      livre : chaque ligne a un montant SIGNÉ (positif = dû par le compte,
      négatif = règlement ou avoir) et un POSTE (bar, épicerie, repas, cagnotte,
      dôme, animaux, charges, divers). Le solde n'est jamais stocké. Ce qui
      reste dû se lit poste par poste : un règlement n'éteint que les dettes de
      son poste, les plus anciennes d'abord, sauf s'il nomme son mois (référence
      « reprise-bar:2026-05 »). Pour diagnostiquer : diagnostic_compte, puis
      lignes_compte ou poste_par_mois. Une ligne rattachée à un décompte émis
      est verrouillée : on la contre-passe, on ne la supprime pas.

      ÉCRITURES. Les outils qui écrivent rendent d'abord un APERÇU et un code de
      confirmation, sans rien écrire. Montre l'aperçu à l'utilisateur et ne
      rappelle l'outil avec `confirmation` qu'après son accord explicite. Tout
      est tracé dans l'historique (PaperTrail), au nom de l'utilisateur.
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
           Finance::RecordSettlement::VentilationMismatch, ExperienceBooking::OutcomeNotRecordable => e
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
