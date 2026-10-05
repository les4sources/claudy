module Mcp
  module Tools
    module Finances
      # Les boutons d'une facture d'achat (PurchaseInvoicesController) :
      # soumettre au paiement, valider ou refuser au nom du pôle, contester,
      # remettre en traitement, payer en espèces.
      class GesteFactureAchat < Ecriture
        include Commun

        GESTES = {
          "soumettre" => "envoyer au paiement : « à valider » si un pôle doit dire oui (ses membres reçoivent un email), " \
                         "sinon « à payer » avec l'écriture d'achat",
          "valider" => "l'aval du pôle (réservé à ses membres et aux comptes sans membre) : la facture passe « à payer »",
          "contester" => "bloquer la facture avec un motif (motif obligatoire) ; si elle attendait la validation, c'est le " \
                         "refus du pôle et la comptabilité est prévenue par email",
          "rouvrir" => "la remettre « à traiter » après correction",
          "payer_en_especes" => "le fournisseur est payé en caisse : crée la sortie de caisse affectée et comptabilisée"
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
                 caisse: { type: "string", description: "Pour payer_en_especes : la caisse, s'il y en a plusieurs." }
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
              prevenus = prevenir_pole(facture)
              "#{ligne_facture(facture)}#{"\nEmail de validation envoyé à #{prevenus.join(', ')}." if prevenus.any?}"
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
            end
          end
        end

        # Le controller prévient le pôle au geste d'envoyer, pas sur un
        # callback : on fait de même.
        def prevenir_pole(facture)
          return [] unless facture.to_validate?

          facture.validation_recipients.map do |human|
            PurchaseInvoiceMailer.validation_requested(facture, human.email).deliver_later
            human.email
          end
        end

        def plan_soumettre(facture, _arguments)
          raise Error, "Cette facture est déjà #{facture.status_label.downcase}." if facture.frozen_content?
          raise Error, "Elle attend déjà la validation du pôle." if facture.to_validate?
          unless facture.balanced?
            raise Error, "Il reste #{euros(facture.total_cents - facture.lines_total_cents)} à ventiler avant de l'envoyer au paiement."
          end

          if facture.next_status == "to_validate"
            destinataires = facture.validation_recipients.map(&:email)
            ["→ À VALIDER par le pôle #{facture.validation_team&.name}. " +
             (destinataires.any? ? "Email de demande de validation à : #{destinataires.join(', ')}." : "Le pôle n'a aucune adresse : à prévenir à la main."), {}]
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

          ["→ À TRAITER (le motif de contestation est effacé).", {}]
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
