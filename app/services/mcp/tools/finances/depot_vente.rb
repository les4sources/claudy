module Mcp
  module Tools
    module Finances
      # Comptabilité > Dépôt-vente (ConsignmentReportsController #index, #show
      # et #yearly) : le mois des artisans, la fiche d'un relevé, et le
      # récapitulatif annuel envoyé au comptable.
      class DepotVente < Base
        include Commun

        tool "depot_vente",
             title: "Dépôt-vente : relevés des artisans",
             description: "Le mois du dépôt-vente : chaque artisan sollicité, son relevé (demandé, déclaré, vérifié, " \
                          "réglé), ventes, commission et net, et les artisans sous contrat sans relevé. Avec `releve` " \
                          "(ou `artisan` et `mois`) : la fiche (lignes déclarées, virements reçus, écart, facture liée, " \
                          "ce qu'il reste à faire). Avec `annee` : le récapitulatif annuel par artisan. Agir : " \
                          "releve_depot_vente.",
             schema: {
               properties: {
                 mois: MOIS.merge(description: "Mois, AAAA-MM. Défaut : le mois en cours."),
                 releve: { type: %w[integer string], description: "Un relevé (#7 ou DV-202608-7)." },
                 artisan: { type: "string", description: "Avec `mois` : le relevé de cet artisan." },
                 annee: { type: "integer", description: "Le récapitulatif de cette année." }
               }
             }

        def call(arguments)
          return recap(arguments["annee"].to_i) if arguments["annee"].present?
          return detail(releve_depot_vente!(arguments)) if arguments["releve"].present? || arguments["artisan"].present?

          mois = mois!(arguments["mois"], defaut: Date.current.beginning_of_month)
          releves = ConsignmentReport.for_month(mois).includes(:consignor, :consignment_report_lines)
                                     .joins(:consignor).merge(Consignor.ordered).to_a
          manquants = Consignor.actives.ordered.select { |c| c.running_on?(mois.end_of_month) } - releves.map(&:consignor)
          lignes = ["Dépôt-vente de #{nom_mois(mois)} : #{releves.size} relevé(s)"]
          lignes += releves.map { |r| ligne_releve_depot(r) }
          lignes << "Sous contrat sans relevé ce mois : #{manquants.map(&:name).join(', ')}" if manquants.any?
          lignes << "Aucun relevé ce mois." if releves.empty? && manquants.empty?
          lignes.join("\n")
        end

        private

        def detail(r)
          artisan = r.consignor
          lignes = r.consignment_report_lines.ordered.map do |l|
            "  ligne ##{l.id} · #{l.label} · #{l.quantity} × #{euros(l.unit_price_cents)} = #{euros(l.amount_cents)}" \
              "#{" · #{l.payment_method_label.downcase}" if l.payment_method.present?}"
          end
          virements = r.bank_transfers.ordered.map { |e| "  ligne ##{e.id} du #{e.entry_date} · #{euros(e.amount_cents)} · #{e.communication}" }
          [ligne_releve_depot(r),
           "Artisan : #{artisan.name}#{" · #{artisan.email}" if artisan.email.present?} · #{artisan.settlement_mode_label}" \
           "#{" · IBAN #{artisan.iban_masked}" if artisan.paid_by_transfer? && artisan.iban.present?} · commission #{r.applied_commission_percent} %",
           ("Notes : #{r.notes}" if r.notes.present?),
           "Lignes déclarées :", *(lignes.presence || ["  aucune"]),
           "Encaissements du mois : virements reçus #{euros(r.received_cents)} · espèces déclarées #{euros(r.cash_declared_cents)} · " \
           "écart #{euros(r.bank_gap_cents)}",
           *virements,
           ("Facture liée : #{ligne_facture(r.purchase_invoice)}" if r.purchase_invoice),
           *candidates(r),
           ("Réglé le #{r.settled_on}" if r.settled_on),
           "À faire : #{a_faire(r)}",
           "Page de l'artisan : #{lien_public(:public_consignment_report, r.token)}"].compact.join("\n")
        end

        def a_faire(r)
          if r.editable_by_admin? then "corriger les lignes si besoin, puis vérifier (releve_depot_vente verifier)."
          elsif r.verified? && r.consignor.paid_by_transfer?
            if !r.posted? then "régler par virement (releve_depot_vente regler)."
            elsif ::Consignments::Repost.new(consignment_report: r).needed?
              "l'écriture ne suit plus le mode de règlement de l'artisan : la repasser (releve_depot_vente repasser), puis le virement."
            else "le virement, dans « À payer » (a_payer)."
            end
          elsif r.verified? then r.purchase_invoice ? "payer la facture liée : son paiement soldera le relevé." : "lier la facture de l'artisan (releve_depot_vente lier_facture)."
          else "rien, il est réglé."
          end
        end

        # Mode « l'artisan facture » : les factures de son tiers, comme à l'écran.
        def candidates(r)
          return [] unless r.consignor.invoice? && r.purchase_invoice.nil? && r.verified?

          tiers = r.consignor.third_party || (r.consignor.human && ThirdParty.find_by(human_id: r.consignor.human_id))
          return ["Aucun tiers connu pour #{r.consignor.name} : cherche sa facture avec factures_achat."] if tiers.nil?

          factures = PurchaseInvoice.where(third_party_id: tiers.id).includes(:third_party, :legal_entity).ordered.limit(10)
          ["Factures candidates (#{tiers.name}) :", *factures.map { |f| "  #{ligne_facture(f)}" }]
        end

        def recap(annee)
          releves = ConsignmentReport.where(period_month: Date.new(annee, 1, 1)..Date.new(annee, 12, 31))
                                     .includes(:consignor, :consignment_report_lines).ordered
          return "Aucun relevé de dépôt-vente en #{annee}." if releves.empty?

          lignes = releves.group_by(&:consignor).sort_by { |artisan, _| artisan.name.to_s }.map do |artisan, liste|
            "#{artisan.name} · #{liste.size} relevé(s), #{liste.count(&:settled?)} réglé(s) · ventes #{euros(liste.sum(&:displayed_gross_cents))} · " \
              "commission #{euros(liste.sum(&:displayed_commission_cents))} · net #{euros(liste.sum(&:displayed_net_cents))}"
          end
          total = "Total #{annee} · ventes #{euros(releves.sum(&:displayed_gross_cents))} · commission " \
                  "#{euros(releves.sum(&:displayed_commission_cents))} · net #{euros(releves.sum(&:displayed_net_cents))}"
          ([total] + lignes + ["Les relevés pas encore vérifiés y entrent avec leurs totaux du moment. L'export CSV est à l'écran."]).join("\n")
        end
      end
    end
  end
end
