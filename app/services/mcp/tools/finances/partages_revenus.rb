module Mcp
  module Tools
    module Finances
      # Comptabilité > Partages de revenus (RevenueShareAgreementsController
      # #index et #show, RevenueShareStatementsController #show) : les accords
      # par hébergement partagé, leurs relevés, et le détail d'un relevé.
      class PartagesRevenus < Base
        include Commun

        tool "partages_revenus",
             title: "Partages de revenus",
             description: "Les accords de partage (un hébergement, un bénéficiaire, une part, une période) avec leurs " \
                          "relevés et la prochaine période close à relever. Avec `accord` : sa fiche. Avec `releve` : " \
                          "les réservations retenues, les régularisations et, sur un brouillon, les réservations " \
                          "écartées et pourquoi. Agir : accord_partage, releve_partage.",
             schema: {
               properties: {
                 accord: { type: %w[integer string], description: "Un accord (#id, hébergement ou bénéficiaire)." },
                 releve: { type: %w[integer string], description: "Un relevé (#3 ou REV-3-202607)." }
               }
             }

        def call(arguments)
          return detail_releve(releve_partage!(arguments["releve"])) if arguments["releve"].present?
          return fiche(accord_partage!(arguments["accord"])) if arguments["accord"].present?

          accords = RevenueShareAgreement.ordered.includes(:lodging, :revenue_share_statements).to_a
          return "Aucun accord de partage." if accords.empty?

          accords.map do |a|
            suivante = a.active? && a.next_period_to_report
            "#{ligne_accord(a)} · #{a.revenue_share_statements.size} relevé(s)" \
              "#{" · à relever : #{a.period_label_for(suivante.first)}" if suivante}"
          end.join("\n")
        end

        private

        def fiche(a)
          suivante = a.next_period_to_report
          [ligne_accord(a),
           "Bénéficiaire : #{a.beneficiary_name} · #{a.beneficiary_email.presence || "sans email (le relevé ne partira pas tout seul)"} · " \
           "#{a.iban_masked || 'sans IBAN'}#{" · tiers #{a.beneficiary_third_party.name}" if a.beneficiary_third_party}",
           suivante ? "Prochaine période à relever : #{a.period_label_for(suivante.first)} (du #{suivante.first} au #{suivante.last})" : "Toutes les périodes closes sont relevées.",
           "Relevés :",
           *(a.revenue_share_statements.recent_first.map { |r| "  #{ligne_releve_partage(r)}" }.presence || ["  aucun"])].join("\n")
        end

        def detail_releve(r)
          accord = r.revenue_share_agreement
          lignes = r.revenue_share_statement_lines.chronological.map do |l|
            "  #{l.kind_label} · #{l.label} · du #{l.from_date} au #{l.to_date} · #{euros(l.amount_cents)} (réservation ##{l.booking_id})"
          end
          ecartees = if r.draft?
                       ::RevenueShares::Selection.new(agreement: accord, period_from: r.period_from, period_to: r.period_to,
                                                      except_statement: r).excluded
                     else
                       []
                     end
          [ligne_releve_partage(r),
           "Du #{r.period_from} au #{r.period_to} · part de #{accord.share_percent} % pour #{accord.beneficiary_name}",
           ("Émis le #{I18n.l(r.issued_at.to_date)}#{r.sent_at ? ", envoyé à #{accord.beneficiary_email}" : ', pas envoyé'}" if r.issued_at),
           "Page du bénéficiaire : #{lien_public(:public_revenue_share_statement, r.token)}",
           "Lignes :", *(lignes.presence || ["  aucune"]),
           *(["Écartées :"] + ecartees.map { |e| "  réservation ##{e.booking.id} du #{e.booking.from_date} · #{e.reason}" } if ecartees.any?)]
            .compact.join("\n")
        end
      end
    end
  end
end
