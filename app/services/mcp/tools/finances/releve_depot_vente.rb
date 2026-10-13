module Mcp
  module Tools
    module Finances
      # Comptabilité > Dépôt-vente, la fiche d'un relevé
      # (ConsignmentReportsController #update, #verify, #settle, #link_invoice,
      # #unlink_invoice et #resend). On corrige ce que l'artisan a déclaré tant
      # que rien n'est figé, on vérifie (les totaux et le taux se figent : c'est
      # une dette), puis on règle par virement ou en liant sa facture.
      class ReleveDepotVente < Ecriture
        include Commun

        GESTES = %w[corriger verifier regler lier_facture detacher_facture renvoyer].freeze

        LIGNE_DECLAREE = {
          type: "object",
          additionalProperties: false,
          properties: {
            ligne: { type: %w[integer string], description: "La ligne à corriger (#id, rendu par depot_vente). Absente : nouvelle ligne." },
            libelle: { type: "string" },
            quantite: { type: "integer" },
            prix_unitaire: MONTANT,
            supprimer: { type: "boolean" }
          }
        }.freeze

        tool "releve_depot_vente",
             title: "Corriger, vérifier, régler un relevé de dépôt-vente",
             description: "Sur un relevé d'artisan (depot_vente). `corriger` : les lignes déclarées (libellé, quantité, " \
                          "prix unitaire, ajout, suppression) et les notes, tant qu'il est demandé ou déclaré. " \
                          "`verifier` : fige ventes, taux et net, le relevé devient une dette. `regler` (artisan payé " \
                          "par virement) : passe l'écriture, le net entre dans « À payer ». `lier_facture` / " \
                          "`detacher_facture` (artisan qui facture) : sa facture d'achat, dont le paiement soldera le " \
                          "relevé. `renvoyer` : ÉCRIT À L'ARTISAN (la demande de déclaration du mois) : dis-le avant.",
             schema: {
               properties: {
                 geste: { type: "string", enum: GESTES },
                 releve: { type: %w[integer string], description: "Le relevé (#7 ou DV-202608-7)." },
                 artisan: { type: "string", description: "Sans `releve` : l'artisan, avec `mois`." },
                 mois: MOIS,
                 lignes: { type: "array", items: LIGNE_DECLAREE, description: "Pour corriger : seules les lignes données changent." },
                 notes: { type: "string" },
                 facture: FACTURE.merge(description: "Pour lier_facture : la facture d'achat de l'artisan (#88).")
               },
               required: %w[geste]
             }

        # `renvoyer` envoie un email : pas de transaction autour du geste.
        def self.transactionnel? = false

        private

        def planifier(arguments)
          geste = arguments["geste"]
          raise Error, "geste : #{GESTES.join(', ')}." unless GESTES.include?(geste)

          releve = releve_depot_vente!(arguments)
          donnees = { geste: geste, id: releve.id }
          resume = case geste
                   when "corriger" then corriger(releve, arguments, donnees)
                   when "verifier" then verification(releve)
                   when "regler" then regler(releve)
                   when "lier_facture" then lier(releve, arguments, donnees)
                   when "detacher_facture" then detacher(releve)
                   when "renvoyer" then renvoyer(releve)
                   end
          Plan.new(resume: resume, empreinte: [etat_de(releve), signature(arguments)], donnees: donnees)
        end

        def corriger(releve, arguments, donnees)
          raise Error, "Ce relevé est #{releve.status_label.downcase} : ses lignes ne se corrigent plus." unless releve.editable_by_admin?

          attributs = {}
          attributs[:notes] = arguments["notes"].to_s.strip.presence if arguments.key?("notes")
          attributs[:consignment_report_lines_attributes] = lignes!(releve, arguments["lignes"]) if arguments["lignes"].present?
          raise Error, "Rien à changer : donne des lignes ou des notes." if attributs.empty?

          donnees[:attributs] = attributs
          apres = simuler { ecrire(releve.id, attributs) }
          "Corriger #{ligne_releve_depot(releve)}\nAprès :\n#{apres}"
        end

        def lignes!(releve, lignes)
          Array(lignes).each_with_index.map do |ligne, index|
            ligne = ligne.to_h
            a = {}
            if ligne["ligne"].present?
              id = id!(ligne["ligne"], "ligne")
              raise Error, "La ligne ##{id} n'est pas sur ce relevé." unless releve.consignment_report_lines.any? { |l| l.id == id }

              a[:id] = id
              next a.merge(_destroy: "1") if ligne["supprimer"]
            elsif ligne["libelle"].blank?
              raise Error, "Ligne #{index + 1} : une nouvelle ligne demande au moins un libellé."
            end
            a[:label] = ligne["libelle"].to_s.strip if ligne["libelle"].present?
            a[:quantity] = ligne["quantite"].to_i if ligne["quantite"].present?
            a[:unit_price_cents] = cents!(ligne["prix_unitaire"], "ligne #{index + 1} prix_unitaire").abs if ligne["prix_unitaire"].present?
            a[:position] = releve.consignment_report_lines.size + index unless a[:id]
            a
          end
        end

        def ecrire(id, attributs)
          releve = ConsignmentReport.find(id)
          metier! { releve.update!(attributs) }
          releve = ConsignmentReport.includes(:consignment_report_lines, :consignor).find(id)
          [ligne_releve_depot(releve),
           *releve.consignment_report_lines.ordered.map { |l| "  #{l.label} · #{l.quantity} × #{euros(l.unit_price_cents)} = #{euros(l.amount_cents)}" }]
            .join("\n")
        end

        def verification(releve)
          apres = simuler { metier! { ::Consignments::Verify.new(consignment_report: ConsignmentReport.find(releve.id), verified_by: user).run! } }
          "Vérifier #{ligne_releve_depot(releve)}\nTotaux figés : ventes #{euros(apres.gross_cents)} · commission " \
            "#{apres.commission_percent} % #{euros(apres.commission_cents)} · net dû à #{releve.consignor.name} #{euros(apres.net_cents)}.\n" \
            "Les lignes ne se corrigeront plus."
        end

        def regler(releve)
          simuler { metier! { ::Consignments::Settle.new(consignment_report: ConsignmentReport.find(releve.id)).run! } }
          "Régler #{ligne_releve_depot(releve)}\nL'écriture d'achat est passée ; #{euros(releve.net_cents)} entrent dans « À payer » " \
            "(virement vers #{releve.consignor.iban_masked || "l'IBAN de l'artisan"}). Ce geste ne paie rien : le paiement se rapproche."
        end

        def lier(releve, arguments, donnees)
          raise Error, "#{releve.consignor.name} est payé·e par virement : règle le relevé (regler)." unless releve.consignor.invoice?

          facture = facture!(arguments["facture"])
          raise Error, "Cette facture est déjà liée à ce relevé." if releve.purchase_invoice_id == facture.id

          donnees[:facture] = facture.id
          "Lier à #{ligne_releve_depot(releve)}\nla #{ligne_facture(facture)}#{"\n(remplace la #{ligne_facture(releve.purchase_invoice)})" if releve.purchase_invoice}\n" \
            "Le paiement de la facture soldera le relevé."
        end

        def detacher(releve)
          raise Error, "Aucune facture n'est liée à ce relevé." if releve.purchase_invoice.nil?

          "Détacher la #{ligne_facture(releve.purchase_invoice)}\ndu #{ligne_releve_depot(releve)}"
        end

        def renvoyer(releve)
          email = releve.consignor.email.presence
          raise Error, "#{releve.consignor.name} n'a pas d'adresse email : donne-lui le lien #{lien_public(:public_consignment_report, releve.token)}." if email.nil?

          "ÉCRIT À L'ARTISAN : renvoyer à #{email} la demande de déclaration de #{releve.period_label}.\n#{ligne_releve_depot(releve)}"
        end

        def appliquer(plan)
          d = plan.donnees
          releve = ConsignmentReport.find(d[:id])
          case d[:geste]
          when "corriger"
            "Relevé corrigé : #{ApplicationRecord.transaction { ecrire(releve.id, d[:attributs]) }}"
          when "verifier"
            releve = metier! { ::Consignments::Verify.new(consignment_report: releve, verified_by: user, whodunnit: whodunnit).run! }
            "Relevé vérifié : #{ligne_releve_depot(releve)}."
          when "regler"
            releve = metier! { ::Consignments::Settle.new(consignment_report: releve, whodunnit: whodunnit).run! }
            "Écriture passée : #{ligne_releve_depot(releve)}. Le virement attend dans « À payer »."
          when "lier_facture", "detacher_facture"
            facture = d[:facture] && PurchaseInvoice.find(d[:facture])
            ApplicationRecord.transaction do
              metier! { releve.update!(purchase_invoice: facture) }
              ::Consignments::RefreshSettlement.new(consignment_report: releve.reload).run!
            end
            facture ? "Facture #{facture.payable_reference} liée au relevé #{releve.reference}." : "Facture détachée du relevé #{releve.reference}."
          when "renvoyer"
            ConsignmentMailer.monthly_request(releve).deliver_later
            releve.update_column(:requested_at, Time.current)
            "Demande renvoyée à #{releve.consignor.email}."
          end
        end
      end
    end
  end
end
