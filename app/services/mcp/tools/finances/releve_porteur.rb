module Mcp
  module Tools
    module Finances
      # Comptabilité > Porteurs (CarrierStatementsController #create, #issue,
      # #repost, #reopen et #destroy, CarrierStatementLinesController). Générer
      # pose un brouillon qu'on relit ; émettre le fige, passe l'écriture et
      # ENVOIE le relevé au porteur. Seul un brouillon se supprime. Repasser
      # suit le « payé via » de la fiche du porteur. Rouvrir contre-passe un
      # relevé émis pour le corriger, ligne par ligne, avant de le réémettre.
      class RelevePorteur < Ecriture
        include Commun

        GESTES = %w[generer emettre supprimer repasser rouvrir corriger_ligne retirer_ligne].freeze

        tool "releve_porteur",
             title: "Générer, émettre, corriger, repasser ou supprimer un relevé de porteur",
             description: "`generer` : un brouillon pour un porteur, avec ses prestations tenues pas encore relevées " \
                          "(défaut : le trimestre précédent). `emettre` : fige le relevé, passe l'écriture (la " \
                          "rémunération entre dans « À payer ») et ÉCRIT AU PORTEUR (email avec le relevé) : dis-le " \
                          "avant qu'il accepte. `supprimer` : retire un brouillon, ses prestations redeviennent " \
                          "disponibles. Un relevé émis ne se supprime pas. `repasser` : un relevé émis, pas encore payé, dont " \
                          "le porteur est payé via un autre tiers depuis (fiche du porteur) : contre-passe l'écriture et " \
                          "la repasse avec la dette au nom de ce tiers, sans email. `rouvrir` : un relevé émis, pas encore " \
                          "payé, redevient brouillon (l'écriture est contre-passée, aucun email) pour être corrigé. Dans un " \
                          "brouillon : `corriger_ligne` (reservation + montant, la réservation suit) et `retirer_ligne` " \
                          "(reservation ; payer: false la passe à 0 € et elle ne revient plus, sinon elle revient au " \
                          "relevé suivant). Puis `emettre` à nouveau. Voir releves_porteurs.",
             schema: {
               properties: {
                 geste: { type: "string", enum: GESTES },
                 porteur: { type: "string", description: "Pour generer : le porteur (nom)." },
                 du: DATE, au: DATE,
                 releve: { type: %w[integer string], description: "Pour tout geste sauf generer : le relevé (#12 ou ACT-12-202607)." },
                 reservation: { type: %w[integer string], description: "Pour corriger_ligne ou retirer_ligne : la réservation de la ligne (#47)." },
                 montant: { type: %w[number string], description: "Pour corriger_ligne : la rémunération juste, en euros (40 ou 40,50 ; 0 accepté)." },
                 payer: { type: "boolean", description: "Pour retirer_ligne : false = ne jamais la payer (0 €) ; défaut true = reportée au relevé suivant." }
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
          when "rouvrir" then planifier_reouverture(releve_porteur!(arguments["releve"]))
          when "corriger_ligne" then planifier_correction(releve_porteur!(arguments["releve"]), arguments)
          when "retirer_ligne" then planifier_retrait(releve_porteur!(arguments["releve"]), arguments)
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

        def planifier_reouverture(releve)
          reouverture = ::CarrierStatements::Reopen.new(statement: releve)
          raise Error, reouverture.refusal unless reouverture.possible?

          resume = ["Rouvrir en brouillon #{ligne_releve_porteur(releve)}",
                    "L'écriture est contre-passée (les deux restent au grand livre) : #{euros(releve.total_fee_cents)} sortent de « À payer ».",
                    "Aucun email ne part. Corrige ensuite les lignes (corriger_ligne, retirer_ligne), puis réémets : " \
                    "le relevé corrigé partira alors à #{releve.recipient_email || 'personne (pas d’email)'}."]
          Plan.new(resume: resume.join("\n"), empreinte: ["rouvrir", etat_de(releve)],
                   donnees: { geste: "rouvrir", id: releve.id })
        end

        def planifier_correction(releve, arguments)
          ligne = ligne_de_releve!(releve, arguments["reservation"])
          texte = arguments["montant"].to_s.strip.delete(" €").tr(",", ".")
          raise Error, "montant : montant illisible « #{arguments['montant']} »." unless texte.match?(/\A\d+(\.\d{1,2})?\z/)

          cents = (BigDecimal(texte) * 100).to_i
          raise Error, "Cette ligne est déjà à #{euros(cents)}." if cents == ligne.fee_cents.to_i

          total = releve.total_fee_cents.to_i - ligne.fee_cents.to_i + cents
          resume = ["Dans #{ligne_releve_porteur(releve)}",
                    "#{ligne.occurred_on} · #{ligne.display_label} (réservation ##{ligne.experience_booking_id}) : " \
                    "#{euros(ligne.fee_cents)} → #{euros(cents)}. La réservation suit.",
                    "Nouveau total du brouillon : #{euros(total)}. Rien ne part."]
          Plan.new(resume: resume.join("\n"), empreinte: ["corriger_ligne", etat_de(releve), etat_de(ligne), cents],
                   donnees: { geste: "corriger_ligne", id: releve.id, ligne: ligne.id, cents: cents })
        end

        def planifier_retrait(releve, arguments)
          ligne = ligne_de_releve!(releve, arguments["reservation"])
          payer = arguments["payer"] != false && arguments["payer"].to_s != "false"
          suite = payer ? "Elle revient au prochain relevé." : "Sa rémunération passe à 0 € : elle ne sera jamais payée."
          resume = ["Retirer de #{ligne_releve_porteur(releve)}",
                    "#{ligne.occurred_on} · #{ligne.display_label} (réservation ##{ligne.experience_booking_id}) · #{euros(ligne.fee_cents)}. #{suite}",
                    "Nouveau total du brouillon : #{euros(releve.total_fee_cents.to_i - ligne.fee_cents.to_i)}. Rien ne part."]
          Plan.new(resume: resume.join("\n"), empreinte: ["retirer_ligne", etat_de(releve), ligne.id, payer],
                   donnees: { geste: "retirer_ligne", id: releve.id, ligne: ligne.id, payer: payer })
        end

        # La ligne d'un brouillon, désignée par sa réservation (#47).
        def ligne_de_releve!(releve, reservation)
          raise Error, "Ce relevé est #{releve.status_label.downcase} : rouvre-le d'abord (geste rouvrir)." unless releve.draft?
          raise Error, "Donne la réservation de la ligne (reservation: 47)." if reservation.blank?

          id = Integer(reservation.to_s.delete("#").strip, exception: false)
          ligne = id && releve.carrier_statement_lines.find_by(experience_booking_id: id)
          raise Error, "La réservation #{reservation} n'est pas sur ce relevé." unless ligne

          ligne
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
          when "rouvrir"
            releve = metier! do
              ::CarrierStatements::Reopen.new(statement: CarrierStatement.find(d[:id]), reason: @motif, whodunnit: whodunnit).run!
            end
            "Relevé rouvert : #{ligne_releve_porteur(releve)}. Corrige ses lignes, puis réémets-le."
          when "corriger_ligne"
            ligne = CarrierStatementLine.find(d[:ligne])
            metier! { ligne.experience_booking.update!(carrier_fee_cents: d[:cents]) }
            "Ligne corrigée : #{ligne_releve_porteur(CarrierStatement.find(d[:id]))}."
          when "retirer_ligne"
            releve = metier! do
              ::CarrierStatements::RemoveLine.new(line: CarrierStatementLine.find(d[:ligne]), pay: d[:payer], whodunnit: whodunnit).run!
            end
            "Ligne retirée : #{ligne_releve_porteur(releve.reload)}."
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
