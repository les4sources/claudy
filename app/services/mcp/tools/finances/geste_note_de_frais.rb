module Mcp
  module Tools
    module Finances
      # Les boutons d'une note de frais ou de mission (ExpenseReportsController) :
      # passer en traitement, rejeter, payer en caisse, annuler le traitement,
      # supprimer.
      class GesteNoteDeFrais < Ecriture
        include Commun

        GESTES = {
          "traiter" => "passer en traitement : numérotée, écriture passée, à rembourser",
          "rejeter" => "rejeter avec un motif (motif obligatoire) ; seule une note enregistrée se rejette",
          "payer_en_especes" => "rembourser en caisse : sortie de caisse affectée et comptabilisée, le membre reçoit l'email « note payée »",
          "annuler_traitement" => "contre-passer l'écriture : la note redevient modifiable (motif obligatoire)",
          "supprimer" => "supprimer une note enregistrée ou rejetée (motif obligatoire)"
        }.freeze

        tool "geste_note_de_frais",
             title: "Geste sur une note de frais",
             description: "Un geste sur une note de frais ou de mission : #{GESTES.map { |cle, sens| "#{cle} (#{sens})" }.join(' ; ')}. " \
                          "Le remboursement par virement se constate depuis la ligne bancaire (rapprocher_ligne).",
             schema: {
               properties: {
                 note: NOTE,
                 geste: { type: "string", enum: GESTES.keys },
                 date: DATE.merge(description: "Pour traiter ou payer_en_especes : la date. Défaut : aujourd'hui."),
                 caisse: { type: "string", description: "Pour payer_en_especes : la caisse, s'il y en a plusieurs." }
               },
               required: %w[note geste]
             }

        private

        def planifier(arguments)
          note = note!(arguments["note"])
          geste = arguments["geste"].to_s
          raise Error, "geste : #{GESTES.keys.join(', ')}." unless GESTES.key?(geste)

          resume, donnees = send("plan_#{geste}", note, arguments)
          Plan.new(resume: "#{ligne_note(note)}\n#{resume}", empreinte: [etat_de(note), signature(arguments)],
                   donnees: donnees.merge(geste: geste, id: note.id))
        end

        def appliquer(plan)
          d = plan.donnees
          note = ExpenseReport.find(d[:id])
          metier! do
            case d[:geste]
            when "traiter"
              ::ExpenseReports::Process.new(expense_report: note, processed_on: d[:date], whodunnit: whodunnit).run!
            when "rejeter"
              ::ExpenseReports::Reject.new(expense_report: note, reason: @motif, whodunnit: whodunnit).run!
            when "payer_en_especes"
              ::ExpenseReports::PayInCash.new(expense_report: note, paid_on: d[:date], cash_account: CashAccount.find(d[:caisse]),
                                              whodunnit: whodunnit).run!
            when "annuler_traitement"
              ::ExpenseReports::Unprocess.new(expense_report: note, whodunnit: whodunnit).run!
            when "supprimer"
              note.soft_delete!
              next "Note ##{note.id} supprimée (suppression douce)."
            end
            ligne_note(ExpenseReport.find(note.id))
          end
        end

        def plan_traiter(note, arguments)
          raise Error, "Seule une note enregistrée passe en traitement (celle-ci est #{note.status_label.downcase})." unless note.recorded?
          raise Error, "Ajoute au moins une ligne avant de la passer en traitement." if note.expense_lines.empty?

          date = date_ou_nil(arguments["date"], "date") || Date.current
          sans_piece = note.expense_lines.count { |l| !l.receipt.attached? }
          ["→ EN TRAITEMENT le #{date} : numéro attribué, écriture de #{euros(note.total_cents)} au journal des achats." \
           "#{"\n⚠ #{sans_piece} ligne(s) sans justificatif." if sans_piece.positive?}" \
           "#{"\n⚠ #{note.human&.name} n'a pas d'IBAN : le virement ne pourra pas partir." if note.human&.iban.blank?}",
           { date: date.iso8601 }]
        end

        def plan_rejeter(note, _arguments)
          motif!({ "motif" => @motif })
          raise Error, "Une note #{note.status_label.downcase} ne se rejette plus : contre-passe-la d'abord." unless note.recorded?

          ["→ REJETÉE, motif « #{@motif} ».", {}]
        end

        def plan_payer_en_especes(note, arguments)
          raise Error, "Seule une note en traitement se paie (celle-ci est #{note.status_label.downcase})." unless note.processing?

          date = date_ou_nil(arguments["date"], "date") || Date.current
          caisses = CashAccount.actives.where(kind: "cash", legal_entity_id: note.legal_entity_id).ordered
          caisse = arguments["caisse"].present? ? par_nom!(caisses, arguments["caisse"], "caisse") : caisses.first
          raise Error, "Aucune caisse active pour #{note.legal_entity&.name}." if caisse.nil?
          raise Error, "#{nom_mois(date.beginning_of_month)} est arrêté : une sortie de caisse ne s'y ajoute plus." if MonthClosing.closed?(date)

          ["Sortie de caisse de #{euros(note.remaining_cents)} le #{date} depuis « #{caisse.name} », comptabilisée. " \
           "La note passe payée et #{note.human&.name} reçoit l'email « note payée ».", { date: date.iso8601, caisse: caisse.id }]
        end

        def plan_annuler_traitement(note, _arguments)
          motif!({ "motif" => @motif })
          raise Error, "Cette note est payée : son règlement se défait d'abord." if note.paid?
          raise Error, "Cette note n'est pas en traitement." unless note.processing?

          ["Contre-passer son écriture (datée d'aujourd'hui) → ENREGISTRÉE, de nouveau modifiable. Son numéro est gardé.", {}]
        end

        def plan_supprimer(note, _arguments)
          motif!({ "motif" => @motif })
          unless note.recorded? || note.rejected?
            raise Error, "Une note #{note.status_label.downcase} ne se supprime pas : elle porte une écriture."
          end

          ["SUPPRIMER la note (suppression douce, retrouvable dans l'historique).", {}]
        end
      end
    end
  end
end
