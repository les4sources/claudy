module Mcp
  module Tools
    module Finances
      # Comptabilité > Porteurs (CarrierStatementsController #create, #issue,
      # #repost et #destroy). Générer pose un brouillon qu'on relit ; émettre le
      # fige, passe l'écriture et ENVOIE le relevé au porteur. Seul un brouillon
      # se supprime. Repasser suit le « payé via » de la fiche du porteur.
      class RelevePorteur < Ecriture
        include Commun

        GESTES = %w[generer emettre supprimer repasser].freeze

        tool "releve_porteur",
             title: "Générer, émettre, repasser ou supprimer un relevé de porteur",
             description: "`generer` : un brouillon pour un porteur, avec ses prestations tenues pas encore relevées " \
                          "(défaut : le trimestre précédent). `emettre` : fige le relevé, passe l'écriture (la " \
                          "rémunération entre dans « À payer ») et ÉCRIT AU PORTEUR (email avec le relevé) : dis-le " \
                          "avant qu'il accepte. `supprimer` : retire un brouillon, ses prestations redeviennent " \
                          "disponibles. Un relevé émis ne se supprime pas. `repasser` : un relevé émis, pas encore payé, dont " \
                          "le porteur est payé via un autre tiers depuis (fiche du porteur) : contre-passe l'écriture et " \
                          "la repasse avec la dette au nom de ce tiers, sans email. Voir releves_porteurs.",
             schema: {
               properties: {
                 geste: { type: "string", enum: GESTES },
                 porteur: { type: "string", description: "Pour generer : le porteur (nom)." },
                 du: DATE, au: DATE,
                 releve: { type: %w[integer string], description: "Pour emettre, repasser ou supprimer : le relevé (#12 ou ACT-12-202607)." }
               },
               required: %w[geste]
             }

        # L'émission envoie un email : le service tient sa transaction, le mail
        # ne part qu'une fois l'écriture validée.
        def self.transactionnel? = false

        private

        def planifier(arguments)
          case arguments["geste"]
          when "generer" then planifier_generation(arguments)
          when "emettre" then planifier_emission(releve_porteur!(arguments["releve"]))
          when "supprimer" then planifier_suppression(releve_porteur!(arguments["releve"]))
          when "repasser" then planifier_repassage(releve_porteur!(arguments["releve"]))
          else raise Error, "geste : #{GESTES.join(', ')}."
          end
        end

        def planifier_generation(arguments)
          porteur = par_nom!(ExperienceBooking.carriers, arguments["porteur"], "porteur")
          defaut_du, defaut_au = ::CarrierStatements::Generate.default_period
          du = arguments["du"].present? ? date!(arguments["du"], "du") : defaut_du
          au = arguments["au"].present? ? date!(arguments["au"], "au") : defaut_au
          apercu = simuler do
            releve = metier! { generation(porteur, du, au).run! }
            [ligne_releve_porteur(releve), *releve.carrier_statement_lines.chronological.map { |l| "  #{l.occurred_on} · #{l.label} · #{euros(l.fee_cents)}" }]
          end
          bookings = ::CarrierStatements::Selection.new(human: porteur, period_from: du, period_to: au).bookings.map(&:id)
          Plan.new(resume: ["Générer un brouillon pour #{porteur.name}, du #{du} au #{au} :", *apercu,
                            "Rien ne part : le brouillon se relit, puis s'émet."].join("\n"),
                   empreinte: ["generer", porteur.id, du, au, bookings],
                   donnees: { geste: "generer", porteur: porteur.id, du: du, au: au })
        end

        def planifier_emission(releve)
          raise Error, "Ce relevé est déjà #{releve.status_label.downcase}." unless releve.draft?
          raise Error, "Ce relevé n'a aucune ligne." if releve.carrier_statement_lines.empty?

          email = releve.recipient_email
          resume = ["Émettre #{ligne_releve_porteur(releve)}",
                    "Le total est figé, l'écriture est passée et la rémunération entre dans « À payer ».",
                    email ? "ÉCRIT #{releve.paid_through? ? "À #{releve.payee_name}" : 'AU PORTEUR'} : le relevé part à #{email}." : "#{releve.payee_name} n'a pas d'email : rien ne part, le lien de sa page sera à partager à la main."]
          Plan.new(resume: resume.join("\n"), empreinte: ["emettre", etat_de(releve), email],
                   donnees: { geste: "emettre", id: releve.id })
        end

        def planifier_suppression(releve)
          raise Error, "Un relevé #{releve.status_label.downcase} ne se supprime pas : passe par une contre-passation." unless releve.draft?

          Plan.new(resume: "Supprimer le brouillon #{ligne_releve_porteur(releve)}\nSes #{releve.carrier_statement_lines.size} prestation(s) redeviennent disponibles.",
                   empreinte: ["supprimer", etat_de(releve)], donnees: { geste: "supprimer", id: releve.id })
        end

        def planifier_repassage(releve)
          repost = ::CarrierStatements::Repost.new(statement: releve)
          raise Error, "Ce relevé est #{releve.status_label.downcase} : il ne se repasse plus." unless releve.issued?
          unless repost.needed?
            raise Error, "Ce relevé est déjà adressé à #{repost.target_name}, comme le dit la fiche de #{releve.human.name}."
          end
          raise Error, "Un virement est déjà rapproché de ce relevé : retire d'abord ce rapprochement." if releve.cash_allocations.any?

          resume = ["Repasser #{ligne_releve_porteur(releve)}",
                    "Adressé aujourd'hui à #{releve.payee_name}, il le sera à #{repost.target_name} (fiche de #{releve.human.name}).",
                    "L'écriture est contre-passée et repassée : même charge, dette de #{euros(releve.total_fee_cents)} au 440000 au nom de #{repost.target_name}.",
                    "Aucun email ne part."]
          Plan.new(resume: resume.join("\n"), empreinte: ["repasser", etat_de(releve), repost.target&.id],
                   donnees: { geste: "repasser", id: releve.id })
        end

        def appliquer(plan)
          d = plan.donnees
          case d[:geste]
          when "generer"
            releve = metier! { generation(Human.find(d[:porteur]), d[:du], d[:au]).run! }
            "Brouillon généré : #{ligne_releve_porteur(releve)}. Relis-le avant de l'émettre."
          when "emettre"
            releve = CarrierStatement.find(d[:id])
            metier! { ::CarrierStatements::Issue.new(statement: releve, whodunnit: whodunnit).run! }
            releve.reload
            envoi = releve.sent_at ? "envoyé à #{releve.recipient_email}" : "pas d'email : partage #{lien_public(:public_carrier_statement, releve.token)}"
            "Relevé émis : #{ligne_releve_porteur(releve)} · #{envoi}."
          when "repasser"
            releve = metier! { ::CarrierStatements::Repost.new(statement: CarrierStatement.find(d[:id]), whodunnit: whodunnit).run! }
            "Relevé repassé : #{ligne_releve_porteur(releve)} · adressé à #{releve.payee_name}."
          when "supprimer"
            releve = CarrierStatement.find(d[:id])
            # Les lignes partent pour de bon, comme à l'écran : l'index unique
            # sur la prestation interdirait sinon de la relever à nouveau.
            CarrierStatement.transaction do
              releve.carrier_statement_lines.destroy_all
              releve.soft_delete!(validate: false)
            end
            "Brouillon supprimé : ses prestations redeviennent disponibles."
          end
        end

        def generation(porteur, du, au)
          ::CarrierStatements::Generate.new(human: porteur, period_from: du, period_to: au, whodunnit: whodunnit)
        end
      end
    end
  end
end
