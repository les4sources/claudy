module Mcp
  module Tools
    module Finances
      # Comptabilité > Échéancier, la fiche d'une échéance
      # (ComplianceDeadlinesController #update, #start, #close et #reopen). La
      # preuve (PDF) se dépose dans Claudy.
      class Echeance < Ecriture
        include Commun

        GESTES = %w[modifier commencer faire sans_objet rouvrir].freeze

        tool "echeance",
             title: "Avancer, clôturer ou rouvrir une échéance",
             description: "Sur une échéance de l'échéancier. `modifier` : la date, la note, ou la facture d'achat qui la " \
                          "solde (échéance de paiement seulement ; « aucune » pour la détacher). `commencer` : en cours. " \
                          "`faire` : faite (aujourd'hui). `sans_objet` : close sans objet. `rouvrir` : de nouveau à " \
                          "faire. Une échéance liée à une facture se clôt quand la facture est payée.",
             schema: {
               properties: {
                 geste: { type: "string", enum: GESTES },
                 echeance: { type: %w[integer string], description: "L'échéance (#id, rendu par echeancier)." },
                 date: DATE.merge(description: "Pour modifier : la nouvelle date d'échéance."),
                 note: { type: "string", description: "Pour modifier : la note (chaîne vide pour l'effacer)." },
                 facture: { type: %w[integer string], description: "Pour modifier : la facture d'achat (#88), ou « aucune »." }
               },
               required: %w[geste echeance]
             }

        private

        def planifier(arguments)
          d = echeance!(arguments["echeance"])
          donnees = { geste: arguments["geste"], id: d.id }
          resume = case arguments["geste"]
                   when "modifier" then modifier(d, arguments, donnees)
                   when "commencer"
                     raise Error, "Cette échéance est déjà #{d.status_label.downcase}." unless d.status == "todo"

                     "Passer en cours : #{ligne_echeance(d)}"
                   when "faire", "sans_objet"
                     raise Error, "Cette échéance se solde par sa facture : elle sera faite quand la facture sera payée." if d.purchase_invoice
                     raise Error, "Cette échéance est déjà #{d.status_label.downcase}." if d.closed?

                     "Clore « #{arguments['geste'] == 'faire' ? 'fait' : 'sans objet'} » le #{Date.current} : #{ligne_echeance(d)}"
                   when "rouvrir"
                     raise Error, "Cette échéance est encore ouverte." unless d.closed?
                     raise Error, "Elle est close par le paiement de sa facture : détache la facture d'abord." if d.settled_by_invoice?

                     "Rouvrir (à faire) : #{ligne_echeance(d)}"
                   else raise Error, "geste : #{GESTES.join(', ')}."
                   end
          Plan.new(resume: resume, empreinte: [etat_de(d), signature(arguments)], donnees: donnees)
        end

        def modifier(d, arguments, donnees)
          a = {}
          a[:due_on] = date!(arguments["date"], "date") if arguments["date"].present?
          a[:note] = arguments["note"].to_s.strip.presence if arguments.key?("note")
          if arguments["facture"].present?
            if arguments["facture"].to_s.strip.match?(/\A(aucune?|non)\z/i)
              a[:purchase_invoice_id] = nil
            else
              raise Error, "Seule une échéance de paiement se lie à une facture." unless d.payment?

              a[:purchase_invoice_id] = facture!(arguments["facture"]).id
            end
          end
          raise Error, "Rien à changer : donne une date, une note ou une facture." if a.empty?

          donnees[:attributs] = a
          apres = simuler { ecrire(d.id, a) }
          "Modifier : #{ligne_echeance(d)}\nAprès : #{apres}"
        end

        def ecrire(id, attributs)
          d = ComplianceDeadline.find(id)
          metier! { d.update!(attributs) }
          ligne_echeance(ComplianceDeadline.includes(:purchase_invoice, compliance_obligation: :legal_entity).find(id))
        end

        def appliquer(plan)
          d = plan.donnees
          echeance = ComplianceDeadline.find(d[:id])
          case d[:geste]
          when "modifier" then return "Échéance mise à jour : #{ecrire(echeance.id, d[:attributs])}"
          when "commencer" then echeance.update!(status: "in_progress")
          when "faire" then echeance.close!(status: "done", user: user)
          when "sans_objet" then echeance.close!(status: "not_applicable", user: user)
          when "rouvrir" then echeance.reopen!
          end
          "Échéance enregistrée : #{ligne_echeance(echeance.reload)}"
        end
      end
    end
  end
end
