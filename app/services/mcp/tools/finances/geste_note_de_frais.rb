module Mcp
  module Tools
    module Finances
      # Les boutons d'une note de frais ou de mission (ExpenseReportsController) :
      # passer en traitement, rejeter, payer en caisse, annuler le traitement,
      # supprimer.
      class GesteNoteDeFrais < Ecriture
        include Commun

        GESTES = {
          "traiter" => "attribuer le compte de charge de chaque ligne (comptes) et passer en traitement : numérotée, écriture passée, à rembourser",
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
                 comptes: {
                   type: "array",
                   description: "Pour traiter : le compte de charge de chaque ligne (celui qui saisit la note ne le choisit pas, " \
                                "c'est la compta qui l'attribue ici). Obligatoire pour chaque ligne qui n'en a pas encore " \
                                "(notes_de_frais montre les lignes avec leur #id). Les trajets d'une note de mission ont " \
                                "« Déplacements » d'office.",
                   items: {
                     type: "object",
                     additionalProperties: false,
                     properties: {
                       ligne: { type: %w[integer string], description: "La ligne de la note (#id)." },
                       compte: COMPTE_GENERAL.merge(description: "Compte de charge (classe 6) ou d'immobilisation (classe 2).")
                     },
                     required: %w[ligne compte]
                   }
                 },
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
              ::ExpenseReports::Process.new(expense_report: note, processed_on: d[:date], accounts: d[:comptes],
                                            whodunnit: whodunnit).run!
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
          comptes = comptes_des_lignes!(note, arguments["comptes"])
          sans_compte = note.expense_lines.reject { |l| l.general_account_id || comptes.key?(l.id.to_s) }
          if sans_compte.any?
            raise Error, "Attribue un compte de charge (comptes) à : " \
                         "#{sans_compte.map { |l| "##{l.id} « #{l.label} »" }.join(', ')}."
          end

          attribues = note.expense_lines.filter_map do |l|
            next unless comptes.key?(l.id.to_s)

            "  ##{l.id} #{l.label} → #{comptes_choisis[comptes[l.id.to_s]]}"
          end
          sans_piece = note.expense_lines.count(&:receipt_missing?)
          ["→ EN TRAITEMENT le #{date} : numéro attribué, écriture de #{euros(note.total_cents)} au journal des achats." \
           "#{"\nComptes attribués :\n#{attribues.join("\n")}" if attribues.any?}" \
           "#{"\n⚠ #{sans_piece} ligne(s) sans justificatif (ni fichier, ni papier)." if sans_piece.positive?}" \
           "#{"\n⚠ #{note.human&.name} n'a pas d'IBAN : le virement ne pourra pas partir." if note.human&.iban.blank?}",
           { date: date.iso8601, comptes: comptes }]
        end

        # { "id de ligne" => id de compte }. Seuls les comptes qu'une note de
        # frais peut porter (classes 6 et 2) sont acceptés.
        def comptes_des_lignes!(note, comptes)
          @comptes_choisis = {}
          Array(comptes).each_with_object({}) do |choix, acc|
            choix = choix.to_h
            id = choix["ligne"].to_s.delete("#")
            ligne = note.expense_lines.find { |l| l.id.to_s == id }
            raise Error, "La ligne ##{id} n'appartient pas à cette note." if ligne.nil?

            compte = compte_general!(choix["compte"])
            unless ExpenseLine::ACCOUNT_CLASSES.include?(compte.klass)
              raise Error, "#{compte} n'est ni un compte de charge (classe 6) ni d'immobilisation (classe 2)."
            end

            @comptes_choisis[compte.id] = compte.to_s
            acc[id] = compte.id
          end
        end

        def comptes_choisis = @comptes_choisis || {}

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
