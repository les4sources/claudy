module Mcp
  module Tools
    module Finances
      # Comptabilité > Échéancier (ComplianceDeadlinesController #index et
      # #show, ComplianceObligationsController#index) : les obligations
      # légales et fiscales de chaque entité et leurs échéances.
      class Echeancier < Base
        include Commun

        BIENTOT = 30
        RECENT = 90

        tool "echeancier",
             title: "Échéancier comptable et légal",
             description: "Les échéances des obligations (TVA, comptes annuels, précompte, assurances…) : en retard, " \
                          "à 30 jours, plus tard, et faites ces 90 derniers jours. Filtrable par entité. Avec " \
                          "`echeance` : le détail (consignes, note, preuve, facture liée et factures candidates pour " \
                          "une échéance de paiement). `obligations: true` : les obligations elles-mêmes, avec leur " \
                          "prochaine échéance. Agir : echeance, obligation.",
             schema: {
               properties: {
                 entite: ENTITE.merge(description: "Facultatif : une seule entité."),
                 echeance: { type: %w[integer string], description: "Une échéance (#id) pour en voir le détail." },
                 obligations: { type: "boolean" }
               }
             }

        def call(arguments)
          return detail(echeance!(arguments["echeance"])) if arguments["echeance"].present?
          return obligations if arguments["obligations"]

          scope = ComplianceDeadline.includes(:purchase_invoice, compliance_obligation: :legal_entity).ordered
          scope = scope.for_entity(entite_meme_inactive!(arguments["entite"]).id) if arguments["entite"].present?
          aujourdhui = Date.current
          ouvertes = scope.outstanding.to_a
          recentes = scope.where(due_on: (aujourdhui - 1.year)..).to_a.select(&:closed?)
                          .select { |d| (d.effective_done_on || d.due_on) >= aujourdhui - RECENT }
          blocs = {
            "En retard" => ouvertes.select { |d| d.due_on < aujourdhui },
            "À #{BIENTOT} jours" => ouvertes.select { |d| d.due_on.between?(aujourdhui, aujourdhui + BIENTOT) },
            "Plus tard" => ouvertes.select { |d| d.due_on > aujourdhui + BIENTOT },
            "Faites ces #{RECENT} jours" => recentes.sort_by { |d| d.effective_done_on || d.due_on }.reverse
          }
          blocs.flat_map { |titre, liste| ["#{titre} (#{liste.size})", *liste.map { |d| "  #{ligne_echeance(d)}" }] }.join("\n")
        end

        private

        def detail(d)
          o = d.compliance_obligation
          [ligne_echeance(d),
           "Obligation ##{o.id} « #{o.title} » · #{o.frequency_label.downcase}#{" · responsable #{o.responsible_user.email}" if o.responsible_user}",
           ("Consignes : #{o.instructions}" if o.instructions.present?),
           ("Note : #{d.note}" if d.note.present?),
           (d.proof.attached? ? "Preuve jointe : #{d.proof.filename}" : "Pas de preuve jointe (elle se dépose dans Claudy)."),
           ("Facture liée : #{ligne_facture(d.purchase_invoice)} · l'échéance sera faite quand elle sera payée." if d.purchase_invoice),
           *candidates(d)].compact.join("\n")
        end

        def candidates(d)
          return [] unless d.payment? && d.purchase_invoice.nil?

          prises = ComplianceDeadline.where.not(id: d.id).where.not(purchase_invoice_id: nil).select(:purchase_invoice_id)
          factures = PurchaseInvoice.where(legal_entity_id: d.legal_entity.id).where(issued_on: (d.due_on - 1.year)..)
                                    .where.not(id: prises).includes(:third_party, :legal_entity).order(issued_on: :desc).limit(15)
          return ["Aucune facture candidate à lier."] if factures.empty?

          ["Factures candidates (echeance modifier, facture) :", *factures.map { |f| "  #{ligne_facture(f)}" }]
        end

        def obligations
          prochaines = ComplianceDeadline.outstanding.ordered.group_by(&:compliance_obligation_id).transform_values(&:first)
          liste = ComplianceObligation.includes(:legal_entity, :responsible_user).ordered
                                      .sort_by { |o| [o.legal_entity.name, o.active? ? 0 : 1, o.title] }
          return "Aucune obligation." if liste.empty?

          liste.map do |o|
            suivante = prochaines[o.id]
            "Obligation ##{o.id} #{o.title} · #{o.legal_entity.name} · #{o.frequency_label.downcase} dès le #{o.first_due_on}" \
              "#{" jusqu'au #{o.ends_on}" if o.ends_on}#{' · paiement' if o.payment}#{" · #{o.responsible_user.email}" if o.responsible_user}" \
              "#{' · INACTIVE' unless o.active?}#{" · prochaine : #{suivante.display_title} le #{suivante.due_on}" if suivante}"
          end.join("\n")
        end
      end
    end
  end
end
