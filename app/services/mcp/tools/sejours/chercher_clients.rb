module Mcp
  module Tools
    module Sejours
      class ChercherClients < Base
        include Commun

        tool "chercher_clients",
             title: "Chercher des clients",
             description: "Cherche les clients des séjours par nom, organisation, e-mail ou téléphone (les chiffres " \
                          "suffisent). Rend leur identifiant, leur contact et leur nombre de séjours.",
             schema: {
               properties: { recherche: { type: "string", description: "Nom, organisation, e-mail ou téléphone." } },
               required: %w[recherche]
             }

        LIMITE = 30

        def call(arguments)
          recherche = arguments["recherche"].to_s.strip
          raise Error, "Donne au moins deux caractères à chercher." if recherche.length < 2

          clients = Customer.search(recherche).with_stay_counts.order(:last_name, :first_name).limit(LIMITE).to_a
          return "Aucun client ne correspond à « #{recherche} »." if clients.empty?

          lignes = clients.map do |client|
            "#{ligne_client(client)} · #{client.stays_count} séjour(s), dont #{client.upcoming_stays_count} à venir" \
              "#{' · fourre-tout' if client.catch_all?}"
          end
          "#{clients.size} client(s)#{" (limité à #{LIMITE})" if clients.size == LIMITE} :\n#{lignes.join("\n")}"
        end
      end
    end
  end
end
