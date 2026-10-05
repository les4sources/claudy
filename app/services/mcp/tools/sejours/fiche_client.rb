module Mcp
  module Tools
    module Sejours
      class FicheClient < Base
        include Commun

        tool "fiche_client",
             title: "Fiche d'un client",
             description: "La fiche d'un client : coordonnées, facturation (TVA, Peppol, adresse), langue, " \
                          "consentements, notes, et la liste de ses séjours avec ce qu'ils doivent encore.",
             schema: { properties: { client: CLIENT }, required: %w[client] }

        def call(arguments)
          client = client!(arguments["client"])
          champs = {
            "Type" => client.organization? ? "organisation" : "particulier",
            "Organisation" => client.organization_name, "Prénom" => client.first_name, "Nom" => client.last_name,
            "E-mail" => client.email, "Téléphone" => client.phone, "Langue" => client.language,
            "TVA" => client.vat_number, "Peppol" => client.peppol_id,
            "Adresse" => [client.address_line, [client.address_zip, client.address_city].compact_blank.join(" "),
                          client.address_country].compact_blank.join(", "),
            "Accepte les nouvelles" => client.marketing_consent ? "oui" : "non",
            "Enquête de satisfaction" => client.nps_eligible ? "oui" : "non"
          }
          lignes = ["Client ##{client.id} — #{client.name}#{' [fourre-tout]' if client.catch_all?}"]
          lignes += champs.filter_map { |nom, valeur| "#{nom} : #{valeur}" if valeur.present? }
          notes = client.notes.to_plain_text.strip
          lignes << "Notes :\n#{notes}" if notes.present?

          sejours = client.stays.includes(:meal_orders, :linen_orders, :experience_bookings, stay_items: :bookable)
                          .order(arrival_date: :desc).limit(50).to_a
          montants = Stays::IndexAmounts.new(sejours).call
          lignes << (sejours.empty? ? "Aucun séjour." : "Séjours :\n#{sejours.map { |s| ligne_sejour(s, montants[s.id]) }.join("\n")}")
          lignes.join("\n")
        end
      end
    end
  end
end
