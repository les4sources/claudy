module Mcp
  module Tools
    module Finances
      # Les boutons d'une facture d'achat (PurchaseInvoicesController) :
      # soumettre au paiement, valider ou refuser au nom du pôle, contester,
      # remettre en traitement, payer en espèces.
      class GesteFactureAchat < Ecriture
        include Commun

        GESTES = {
          "soumettre" => "envoyer au paiement : « à valider » si un pôle doit dire oui (ses membres la reçoivent dans le récapitulatif email du lundi), " \
                         "sinon « à payer » avec l'écriture d'achat",
          "valider" => "l'aval du pôle (réservé à ses membres et aux comptes sans membre) : la facture passe « à payer »",
          "contester" => "bloquer la facture avec un motif (motif obligatoire) ; si elle attendait la validation, c'est le " \
                         "refus du pôle et la comptabilité est prévenue par email",
          "rouvrir" => "la remettre « à traiter » après correction (payée par un membre : la détache de sa note de frais)",
          "payer_en_especes" => "le fournisseur est payé en caisse : crée la sortie de caisse affectée et comptabilisée",
          "payee_par_membre" => "un membre l'a payée en magasin et se la fait rembourser : la dépense va sur sa note de " \
                                "frais (`membre`, ajoutée à sa note enregistrée ou à une nouvelle) ou se relie à celle " \
                                "qu'il a déjà déclarée (`depense`), et c'est la note qui porte la charge ; la facture ne " \
                                "se comptabilise pas"
        }.freeze

        # L'aval signé au nom de Claude, comme toute écriture du connecteur :
        # le service le signerait sinon de l'e-mail seul.
        class Validation < ::PurchaseInvoices::Validate
          def initialize(signature:, **options)
            super(**options)
            @signature = signature
          end

          private

          def whodunnit = @signature
        end

        tool "geste_facture_achat",
             title: "Geste sur une facture d'achat",
             description: "Un geste sur une facture d'achat : #{GESTES.map { |cle, sens| "#{cle} (#{sens})" }.join(' ; ')}. " \
                          "Le paiement par virement se constate depuis la ligne bancaire (rapprocher_ligne).",
             schema: {
               properties: {
                 facture: FACTURE,
                 geste: { type: "string", enum: GESTES.keys },
                 date: DATE.merge(description: "Pour payer_en_especes : la date du paiement. Défaut : aujourd'hui."),
                 caisse: { type: "string", description: "Pour payer_en_especes : la caisse, s'il y en a plusieurs." },
                 membre: { type: "string", description: "Pour payee_par_membre : le membre qui a payé (nom, ou « moi »)." },
                 depense: { type: ["integer", "string"],
                            description: "Pour payee_par_membre : la ligne de note de frais (#id) qu'il a déjà déclarée pour " \
                                         "cet achat, au même montant. L'aperçu sans membre ni dépense liste les candidates." }
               },
               required: %w[facture geste]
             }

        # Des emails partent (pôle, comptabilité) : chaque service tient sa
        # transaction, l'email ne part qu'après.
        def self.transactionnel? = false

        private

        def planifier(arguments)
          facture = facture!(arguments["facture"])
          geste = arguments["geste"].to_s
          raise Error, "geste : #{GESTES.keys.join(', ')}." unless GESTES.key?(geste)

          resume, donnees = send("plan_#{geste}", facture, arguments)
          Plan.new(resume: "#{ligne_facture(facture)}\n#{resume}", empreinte: [etat_de(facture), signature(arguments)],
                   donnees: donnees.merge(geste: geste, id: facture.id))
        end

        def appliquer(plan)
          d = plan.donnees
          facture = PurchaseInvoice.find(d[:id])
          metier! do
            case d[:geste]
            when "soumettre"
              facture = ::PurchaseInvoices::Advance.new(purchase_invoice: facture, whodunnit: whodunnit).submit!
              "#{ligne_facture(facture)}#{"\nLe pôle la retrouvera dans le récapitulatif de lundi matin." if facture.to_validate?}"
            when "valider"
              Validation.new(signature: whodunnit, purchase_invoice: facture, user: user).approve!
              "Facture validée : #{ligne_facture(facture.reload)}"
            when "contester"
              if facture.to_validate?
                Validation.new(signature: whodunnit, purchase_invoice: facture, user: user).reject!(@motif)
                "Facture refusée par le pôle, la comptabilité est prévenue : #{ligne_facture(facture.reload)}"
              else
                ::PurchaseInvoices::Advance.new(purchase_invoice: facture, whodunnit: whodunnit).dispute!(@motif)
                "Facture contestée : #{ligne_facture(facture.reload)}"
              end
            when "rouvrir"
              ::PurchaseInvoices::Advance.new(purchase_invoice: facture, whodunnit: whodunnit).reopen!
              "Facture remise en traitement : #{ligne_facture(facture.reload)}"
            when "payer_en_especes"
              ::PurchaseInvoices::PayInCash.new(purchase_invoice: facture, paid_on: d[:date], cash_account: CashAccount.find(d[:caisse]),
                                                whodunnit: whodunnit).run!
              "Facture payée en espèces, sortie de caisse enregistrée : #{ligne_facture(facture.reload)}"
            when "payee_par_membre"
              note = ::PurchaseInvoices::PaidByMember.new(
                purchase_invoice: facture, user: user, whodunnit: whodunnit,
                human: (Human.find(d[:membre]) if d[:membre]), expense_line: (ExpenseLine.find(d[:depense]) if d[:depense])
              ).run!
              "Facture payée par un membre : #{ligne_facture(facture.reload)}\nRemboursée par #{ligne_note(note.reload)}"
            end
          end
        end

        def plan_soumettre(facture, _arguments)
          raise Error, "Cette facture est déjà #{facture.status_label.downcase}." if facture.frozen_content?
          raise Error, "Elle attend déjà la validation du pôle." if facture.to_validate?
          raise Error, "Elle est payée par un membre : sa note de frais la rembourse. Rouvre-la d'abord si ce n'est pas le cas." if facture.member_paid?
          unless facture.balanced?
            raise Error, "Il reste #{euros(facture.total_cents - facture.lines_total_cents)} à ventiler avant de l'envoyer au paiement."
          end

          if facture.next_status == "to_validate"
            destinataires = facture.validation_recipients.map(&:email)
            ["→ À VALIDER par le pôle #{facture.validation_team&.name}. " +
             (destinataires.any? ? "Elle sera dans le récapitulatif des factures à valider de lundi matin, envoyé à : #{destinataires.join(', ')}." : "Le pôle n'a aucune adresse : à prévenir à la main."), {}]
          else
            ["→ À PAYER : l'écriture d'achat est passée au journal.", {}]
          end
        end

        def plan_valider(facture, _arguments)
          raise Error, "Cette facture n'attend pas de validation (#{facture.status_label.downcase})." unless facture.to_validate?
          raise Error, "Seuls les membres du pôle #{facture.validation_team&.name} peuvent la valider." unless facture.validatable_by?(user)

          ["Valider au nom du pôle #{facture.validation_team&.name} → À PAYER, écriture d'achat passée.", {}]
        end

        def plan_contester(facture, _arguments)
          motif!({ "motif" => @motif })
          raise Error, "Cette facture est déjà comptabilisée : elle se corrige par contre-passation." if facture.frozen_content?
          raise Error, "Elle est payée par un membre : rouvre-la d'abord." if facture.member_paid?

          if facture.to_validate?
            raise Error, "Seuls les membres du pôle #{facture.validation_team&.name} peuvent la refuser." unless facture.validatable_by?(user)

            emails = NotificationSettingsController.accounting_emails
            ["Refuser au nom du pôle → CONTESTÉE, motif « #{@motif} ». Email à la comptabilité : #{emails.join(', ').presence || 'personne'}.", {}]
          else
            ["→ CONTESTÉE, motif « #{@motif} ». Le paiement est bloqué jusqu'à correction.", {}]
          end
        end

        def plan_rouvrir(facture, _arguments)
          raise Error, "Cette facture est déjà comptabilisée : elle se corrige par contre-passation." if facture.frozen_content?
          raise Error, "Elle est déjà à traiter." if facture.to_process?

          if facture.member_paid?
            notes = facture.settling_expense_reports.map { |note| note.reference.presence || "##{note.id}" }
            return ["→ À TRAITER, détachée de sa note de frais#{" (#{notes.join(', ')})" if notes.any?}. La dépense reste " \
                    "sur la note : à en retirer si elle n'est pas à rembourser.", {}]
          end

          ["→ À TRAITER (le motif de contestation est effacé).", {}]
        end

        def plan_payee_par_membre(facture, arguments)
          unless ::PurchaseInvoices::PaidByMember::OPEN_STATUSES.include?(facture.status)
            raise Error, "Cette facture est #{facture.status_label.downcase} : seule une facture à traiter, à valider ou " \
                         "contestée (pas encore comptabilisée) passe en payée par un membre."
          end

          candidates = ::PurchaseInvoices::PaidByMember.candidate_lines(facture)
          if arguments["depense"].present?
            ligne = candidates.find_by(id: arguments["depense"].to_s.delete_prefix("#"))
            raise Error, "Cette dépense ne peut pas régler la facture (même montant, même entité, note non rejetée, pas déjà reliée)." if ligne.nil?

            note = ligne.expense_report
            return ["→ PAYÉE PAR UN MEMBRE : reliée à la dépense ##{ligne.id} « #{ligne.label} » de #{ligne_note(note)}. " \
                    "Rien n'est ajouté à la note, qui porte déjà la charge ; la facture ne se comptabilise pas.",
                    { depense: ligne.id }]
          end

          if arguments["membre"].blank?
            liste = candidates.limit(10).map do |l|
              "  dépense ##{l.id} · #{l.expense_report.reference.presence || "note ##{l.expense_report_id}"} · " \
                "#{l.expense_report.human&.name} · #{l.spent_on} · #{l.label}"
            end
            raise Error, "Donne le membre qui a payé (`membre`)#{", ou la dépense déjà déclarée (`depense`) :\n#{liste.join("\n")}" if liste.any?}."
          end

          humain = membre!(arguments["membre"])
          ouverte = ExpenseReport.where(kind: "expenses", human: humain, legal_entity: facture.legal_entity, status: "recorded")
                                 .recent_first.first
          lignes = facture.purchase_invoice_lines.any? && facture.balanced? ? facture.purchase_invoice_lines.size : 1
          cible = ouverte ? "ajoutée à #{ligne_note(ouverte)}" : "sur une NOUVELLE note de frais de #{humain.name}"
          ["→ PAYÉE PAR UN MEMBRE : #{lignes} dépense(s) de #{euros(facture.total_cents)} #{cible}, avec la pièce de la " \
           "facture comme justificatif et ses comptes et pôles. La note portera la charge ; la facture ne se comptabilise pas.",
           { membre: humain.id }]
        end

        def plan_payer_en_especes(facture, arguments)
          raise Error, "Seule une facture « à payer » se règle en espèces." unless facture.to_pay?

          date = date_ou_nil(arguments["date"], "date") || Date.current
          caisses = CashAccount.actives.where(kind: "cash", legal_entity_id: facture.legal_entity_id).ordered
          caisse = arguments["caisse"].present? ? par_nom!(caisses, arguments["caisse"], "caisse") : caisses.first
          raise Error, "Aucune caisse active pour #{facture.legal_entity&.name}." if caisse.nil?
          raise Error, "#{nom_mois(date.beginning_of_month)} est arrêté : une sortie de caisse ne s'y ajoute plus." if MonthClosing.closed?(date)

          ["Sortie de caisse de #{euros(facture.remaining_cents)} le #{date} depuis « #{caisse.name} », affectée à la dette " \
           "fournisseur et comptabilisée. La facture passe payée.", { date: date.iso8601, caisse: caisse.id }]
        end
      end
    end
  end
end
