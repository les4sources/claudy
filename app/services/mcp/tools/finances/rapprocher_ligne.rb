module Mcp
  module Tools
    module Finances
      # Les rapprochements de la file « À affecter » (CashEntriesController) :
      # une ligne bancaire qui paie une facture, rembourse une note de frais,
      # règle le compte d'un habitant, vire à un membre son crédit, paie un
      # séjour, une facture de vente ou porte un versement Stripe. Chaque fois,
      # l'affectation et le document avancent ensemble ou pas du tout.
      class RapprocherLigne < Ecriture
        include Commun

        AVEC = {
          "facture_achat" => "payer une facture d'achat « à payer » (ligne sortante ; `facture`, `montant` facultatif)",
          "note_de_frais" => "rembourser une note en traitement (ligne sortante ; `note`, `montant` facultatif)",
          "virement_membre" => "virer à un membre le crédit de son compte courant (ligne sortante ; `compte`, `montant` facultatif)",
          "reglement_membre" => "encaisser le règlement d'un habitant sur son compte courant (ligne entrante ; `compte`, " \
                                "`poste` et `montant` facultatifs)",
          "sejour" => "ventiler le paiement d'un séjour selon son devis (ligne entrante ; `sejour`)",
          "facture_vente" => "encaisser une facture de vente émise (ligne entrante ; `facture_vente`)",
          "versement_stripe" => "rapprocher un versement Stripe de la banque (ligne entrante ; `versement_stripe`)"
        }.freeze

        tool "rapprocher_ligne",
             title: "Rapprocher une ligne de trésorerie",
             description: "Rapproche une ligne de la file « À affecter » de ce qu'elle paie : " \
                          "#{AVEC.map { |cle, sens| "#{cle} = #{sens}" }.join(' ; ')}. Les pistes se lisent dans " \
                          "fiche_ligne_tresorerie. La ligne se comptabilise dès qu'elle est entièrement affectée.",
             schema: {
               properties: {
                 ligne: LIGNE,
                 avec: { type: "string", enum: AVEC.keys },
                 facture: FACTURE,
                 note: NOTE,
                 compte: COMPTE,
                 poste: POSTE.merge(description: "Pour reglement_membre : le poste payé. Défaut : celui que devine Claudy."),
                 montant: MONTANT.merge(description: "Montant à imputer, si ce n'est pas tout ce que la ligne peut porter."),
                 sejour: { type: %w[integer string], description: "Le séjour (#1234)." },
                 facture_vente: { type: %w[integer string], description: "La facture de vente (#id)." },
                 versement_stripe: { type: %w[integer string], description: "Le versement Stripe (#id)." }
               },
               required: %w[ligne avec]
             }

        private

        def planifier(arguments)
          entry = ligne!(arguments["ligne"])
          avec = arguments["avec"].to_s
          raise Error, "avec : #{AVEC.keys.join(', ')}." unless AVEC.key?(avec)
          raise Error, "Cette ligne est exclue." if entry.status == "excluded"
          raise Error, "Cette ligne est comptabilisée : annule d'abord sa passation." if entry.posted?

          cible, quoi = cible!(avec, arguments)
          montant = arguments["montant"].present? ? cents!(arguments["montant"], "montant").abs : nil
          donnees = { id: entry.id, avec: avec, cible: cible.id, montant: montant,
                      poste: arguments["poste"].present? ? poste!(arguments["poste"]) : nil }

          apres = simuler { rapprocher(CashEntry.find(entry.id), donnees) }
          resume = [ligne_tresorerie(entry), "Rapprocher de #{quoi}#{" pour #{euros(montant)}" if montant}", "Après : #{apres}"]
          resume << "Un email « note payée » partira au membre une fois la note couverte." if avec == "note_de_frais"
          Plan.new(resume: resume.join("\n"),
                   empreinte: [etat_de(entry), etat_de(cible), entry.cash_allocations.map(&:id).sort, signature(arguments)],
                   donnees: donnees)
        end

        def appliquer(plan)
          rapprocher(CashEntry.find(plan.donnees[:id]), plan.donnees)
        end

        def cible!(avec, arguments)
          case avec
          when "facture_achat"
            facture = facture!(arguments["facture"])
            [facture, ligne_facture(facture)]
          when "note_de_frais"
            note = note!(arguments["note"])
            [note, ligne_note(note)]
          when "virement_membre", "reglement_membre"
            compte = compte!(arguments["compte"])
            [compte, "#{compte.code} — #{compte.name} (#{postes_dus(compte)})"]
          when "sejour"
            raise Error, "Donne le séjour." if arguments["sejour"].blank?

            stay = Stay.find_by(id: id!(arguments["sejour"], "séjour")) || raise(Error, "Aucun séjour ##{arguments['sejour']}.")
            [stay, "séjour ##{stay.id} — #{stay.decorate.display_name} (#{stay.arrival_date} → #{stay.departure_date})"]
          when "facture_vente"
            raise Error, "Donne la facture de vente." if arguments["facture_vente"].blank?

            facture = SalesInvoice.find_by(id: id!(arguments["facture_vente"], "facture de vente")) ||
                      raise(Error, "Aucune facture de vente ##{arguments['facture_vente']}.")
            [facture, "#{facture.label} · #{facture.customer_name} · #{euros(facture.total_cents)} · #{facture.status_label}"]
          when "versement_stripe"
            raise Error, "Donne le versement Stripe." if arguments["versement_stripe"].blank?

            versement = StripePayout.find_by(id: id!(arguments["versement_stripe"], "versement")) ||
                        raise(Error, "Aucun versement Stripe ##{arguments['versement_stripe']}.")
            [versement, "versement Stripe #{versement.account_label} de #{euros(versement.amount_cents)} arrivé le #{versement.arrival_date}"]
          end
        end

        def rapprocher(entry, d)
          metier! do
            case d[:avec]
            when "facture_achat"
              ::Finance::RecordInvoicePayment.new(purchase_invoice: PurchaseInvoice.find(d[:cible]), cash_entry: entry,
                                                  amount_cents: d[:montant], whodunnit: whodunnit).run!
              facture = PurchaseInvoice.find(d[:cible])
              "#{ligne_tresorerie(entry.reload)}\n#{facture.payable_label} : reste #{euros(facture.remaining_cents)}"
            when "note_de_frais"
              ::Finance::RecordExpenseReportPayment.new(expense_report: ExpenseReport.find(d[:cible]), cash_entry: entry,
                                                        amount_cents: d[:montant], whodunnit: whodunnit).run!
              note = ExpenseReport.find(d[:cible])
              "#{ligne_tresorerie(entry.reload)}\n#{note.payable_label} : reste #{euros(note.remaining_cents)}"
            when "virement_membre"
              ::Finance::RecordMemberPayout.new(member_account: MemberAccount.find(d[:cible]), cash_entry: entry,
                                                amount_cents: d[:montant], whodunnit: whodunnit).run!
              compte = MemberAccount.find(d[:cible])
              "#{ligne_tresorerie(entry.reload)}\n#{compte.code} : #{postes_dus(compte)}"
            when "reglement_membre"
              ::Finance::RecordMemberSettlement.new(member_account: MemberAccount.find(d[:cible]), cash_entry: entry,
                                                    amount_cents: d[:montant], flow: d[:poste], whodunnit: whodunnit).run!
              compte = MemberAccount.find(d[:cible])
              "#{ligne_tresorerie(entry.reload)}\n#{compte.code} : #{postes_dus(compte)}"
            when "sejour" then ventiler_sejour(entry, Stay.find(d[:cible]))
            when "facture_vente"
              lignes = ::Finance::RecordSalesInvoicePayment.new(sales_invoice: SalesInvoice.find(d[:cible]), cash_entry: entry,
                                                                whodunnit: whodunnit).run!
              "#{ligne_tresorerie(entry.reload)}\n#{lignes.size} ligne(s) de recette ; l'IBAN est mémorisé pour ce client."
            when "versement_stripe"
              ::Finance::RecordStripePayoutReconciliation.new(stripe_payout: StripePayout.find(d[:cible]), cash_entry: entry,
                                                              whodunnit: whodunnit).run!
              ligne_tresorerie(entry.reload)
            end
          end
        end

        # Le geste « Ventiler » de la file : les lignes viennent du devis du
        # séjour, la base est l'argent reçu, l'IBAN est appris pour ce client.
        def ventiler_sejour(entry, stay)
          entite = entry.cash_account.legal_entity
          entry.lock!
          lignes = ::Finance::VentilateStay.new(stay: stay, amount_cents: entry.reload.amount_cents).run!
          lignes.each do |ligne|
            entry.cash_allocations.create!(general_account: ligne.general_account, team: ligne.team, legal_entity: entite,
                                           amount_cents: ligne.amount_cents, document: stay, label: ligne.label)
          end
          CustomerBankAccount.remember!(customer: stay.customer, iban: entry.counterparty_iban, holder_name: entry.counterparty_name)
          ::Accounting::PostCashEntry.new(cash_entry: entry, whodunnit: whodunnit).run! if entry.reload.fully_allocated?

          "#{ligne_tresorerie(entry.reload)}\nVentilation : " +
            lignes.map { |l| "#{euros(l.amount_cents)} → #{l.general_account&.code}#{" · pôle #{l.team.name}" if l.team} (#{l.label})" }.join(", ")
        end
      end
    end
  end
end
