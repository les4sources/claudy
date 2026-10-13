module Mcp
  module Tools
    module Finances
      # Comptabilité > Partages de revenus, les relevés
      # (RevenueShareStatementsController #create, #issue, #destroy et
      # #mark_paid). Générer pose un brouillon ; émettre le fige, passe
      # l'écriture et ENVOIE le relevé au bénéficiaire.
      class RelevePartage < Ecriture
        include Commun

        GESTES = %w[generer emettre supprimer marquer_paye].freeze

        tool "releve_partage",
             title: "Générer, émettre, payer un relevé de partage de revenus",
             description: "`generer` : le brouillon d'un accord pour une période (défaut : la plus ancienne période " \
                          "close pas encore relevée). `emettre` : fige le relevé, passe l'écriture et ÉCRIT AU " \
                          "BÉNÉFICIAIRE (email avec le relevé) : dis-le avant qu'il accepte. `supprimer` : retire un " \
                          "brouillon (un relevé émis se régularise au suivant). `marquer_paye` : constate le " \
                          "reversement d'un relevé émis, à la date donnée. Voir partages_revenus.",
             schema: {
               properties: {
                 geste: { type: "string", enum: GESTES },
                 accord: { type: %w[integer string], description: "Pour generer : l'accord (#id, hébergement ou bénéficiaire)." },
                 periode: DATE.merge(description: "Pour generer : le premier jour de la période (2026-07-01)."),
                 releve: { type: %w[integer string], description: "Pour les autres gestes : le relevé (#3 ou REV-3-202607)." },
                 date: DATE.merge(description: "Pour marquer_paye : date du reversement. Défaut : aujourd'hui.")
               },
               required: %w[geste]
             }

        # L'émission envoie un email : le service tient sa transaction.
        def self.transactionnel? = false

        private

        def planifier(arguments)
          geste = arguments["geste"]
          raise Error, "geste : #{GESTES.join(', ')}." unless GESTES.include?(geste)
          return planifier_generation(arguments) if geste == "generer"

          releve = releve_partage!(arguments["releve"])
          donnees = { geste: geste, id: releve.id }
          resume = case geste
                   when "emettre" then emettre(releve)
                   when "supprimer"
                     raise Error, "Un relevé #{releve.status_label.downcase} ne se supprime pas : il se régularise au relevé suivant." unless releve.draft?

                     "Supprimer le brouillon #{ligne_releve_partage(releve)}"
                   when "marquer_paye"
                     raise Error, "Seul un relevé émis peut être marqué payé (celui-ci est #{releve.status_label.downcase})." unless releve.issued?

                     donnees[:date] = arguments["date"].present? ? date!(arguments["date"], "date") : Date.current
                     "Marquer payé le #{donnees[:date]} : #{ligne_releve_partage(releve)}"
                   end
          Plan.new(resume: resume, empreinte: [etat_de(releve), signature(arguments)], donnees: donnees)
        end

        def planifier_generation(arguments)
          accord = accord_partage!(arguments["accord"])
          periode = if arguments["periode"].present?
                      accord.period_start_for(date!(arguments["periode"], "periode"))
                    else
                      accord.next_period_to_report&.first || raise(Error, "Aucune période close ne reste à relever pour cet accord.")
                    end
          apercu = simuler do
            releve = metier! { generation(accord, periode).run! }
            [ligne_releve_partage(releve),
             *releve.revenue_share_statement_lines.chronological.map { |l| "  #{l.kind_label} · #{l.label} · #{euros(l.amount_cents)}" }]
          end
          Plan.new(resume: ["Générer le relevé #{accord.period_label_for(periode)} de #{ligne_accord(accord)} :", *apercu,
                            "Rien ne part : le brouillon se relit, puis s'émet."].join("\n"),
                   empreinte: ["generer", etat_de(accord), periode, retenues(accord, periode)],
                   donnees: { geste: "generer", accord: accord.id, periode: periode })
        end

        def emettre(releve)
          raise Error, "Ce relevé est déjà #{releve.status_label.downcase}." unless releve.draft?
          raise Error, "Ce relevé n'a aucune ligne." if releve.revenue_share_statement_lines.empty?

          email = releve.revenue_share_agreement.beneficiary_email.presence
          ["Émettre #{ligne_releve_partage(releve)}",
           "Le relevé est figé et l'écriture du reversement est passée.",
           email ? "ÉCRIT AU BÉNÉFICIAIRE : le relevé part à #{email}." : "Aucun email de bénéficiaire : rien ne part, le lien de la page sera à partager à la main."]
            .join("\n")
        end

        def appliquer(plan)
          d = plan.donnees
          if d[:geste] == "generer"
            releve = metier! { generation(RevenueShareAgreement.find(d[:accord]), d[:periode]).run! }
            return "Brouillon généré : #{ligne_releve_partage(releve)}. Relis-le avant de l'émettre."
          end

          releve = RevenueShareStatement.find(d[:id])
          case d[:geste]
          when "emettre"
            metier! { ::RevenueShares::Issue.new(statement: releve, whodunnit: whodunnit).run! }
            releve.reload
            envoi = releve.sent_at ? "envoyé à #{releve.revenue_share_agreement.beneficiary_email}" : "pas d'email : partage #{lien_public(:public_revenue_share_statement, releve.token)}"
            "Relevé émis : #{ligne_releve_partage(releve)} · #{envoi}."
          when "supprimer"
            releve.destroy
            "Brouillon supprimé."
          when "marquer_paye"
            metier! { releve.update!(status: "paid", paid_on: d[:date]) }
            "Relevé marqué payé : #{ligne_releve_partage(releve)}."
          end
        end

        # Ce que le brouillon retiendra, pour que la confirmation refuse si une
        # réservation a bougé depuis l'aperçu.
        def retenues(accord, periode)
          ::RevenueShares::Selection.new(agreement: accord, period_from: periode, period_to: accord.period_end_for(periode))
                                    .retained.map { |l| [l.booking.id, l.kind, l.amount_cents] }
        end

        def generation(accord, periode)
          ::RevenueShares::Generate.new(agreement: accord, period_from: periode, whodunnit: whodunnit)
        end
      end
    end
  end
end
