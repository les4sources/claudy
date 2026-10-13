module Mcp
  module Tools
    module Finances
      # Comptabilité > Porteurs (CarrierStatementsController #index et #show) :
      # ce que chaque porteur a tenu sans l'avoir encore relevé, ses relevés,
      # et le détail d'un relevé.
      class RelevesPorteurs < Base
        include Commun

        tool "releves_porteurs",
             title: "Relevés des porteurs d'activité",
             description: "Par porteur d'activité : les prestations tenues pas encore relevées (nombre, rémunération) et " \
                          "ses relevés (brouillon, émis, payé). Avec `releve` : le détail d'un relevé, ligne par " \
                          "prestation. Générer, émettre ou supprimer un brouillon : releve_porteur.",
             schema: {
               properties: {
                 releve: { type: %w[integer string], description: "Un relevé (#12 ou ACT-12-202607) pour en voir le détail." },
                 porteur: { type: "string", description: "Limiter à un porteur (nom)." }
               }
             }

        def call(arguments)
          return detail(releve_porteur!(arguments["releve"])) if arguments["releve"].present?

          porteurs = ExperienceBooking.carriers.order(:name)
          porteurs = porteurs.where(id: par_nom!(porteurs, arguments["porteur"], "porteur").id) if arguments["porteur"].present?
          du, au = ::CarrierStatements::Generate.default_period
          blocs = porteurs.filter_map do |porteur|
            selection = ::CarrierStatements::Selection.new(human: porteur)
            releves = CarrierStatement.where(human: porteur).recent_first.to_a
            next if selection.bookings.empty? && releves.empty?

            lignes = ["#{porteur.name}#{" (#{porteur.email})" if porteur.email.present?}" \
                      "#{" · payé via #{porteur.carrier_payee.name}" if porteur.carrier_payee} · à relever : " \
                      "#{selection.bookings.size} prestation(s), #{euros(selection.total_fee_cents)}"]
            lignes + releves.map { |r| "  #{ligne_releve_porteur(r)}" }
          end
          entete = "Période par défaut d'une génération : du #{du} au #{au} (trimestre précédent)."
          return "#{entete}\nAucun porteur n'a de prestation tenue ni de relevé." if blocs.empty?

          ([entete] + blocs.flatten).join("\n")
        end

        private

        def detail(releve)
          lignes = releve.carrier_statement_lines.chronological.includes(experience_booking: { experience_availability: :experience })
          [ligne_releve_porteur(releve),
           "Porteur : #{releve.human.name}#{" · adressé à #{releve.third_party.name}" if releve.paid_through?}" \
           "#{releve.recipient_email ? " · #{releve.recipient_email}" : ' · sans email'}",
           ("Émis le #{I18n.l(releve.issued_at.to_date)}#{releve.sent_at ? ', envoyé' : ', pas envoyé (aucun email)'}" if releve.issued_at),
           ("Comptabilisé · paiement dans « À payer »" if releve.posted?),
           "Page du porteur : #{lien_public(:public_carrier_statement, releve.token)}",
           "Prestations :",
           *lignes.map { |l| "  #{l.occurred_on} · #{l.label} · #{euros(l.fee_cents)} (réservation ##{l.experience_booking_id})" }]
            .compact.join("\n")
        end
      end
    end
  end
end
