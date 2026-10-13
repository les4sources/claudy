module Mcp
  module Tools
    module Finances
      # Ce que partagent les outils des finances : la trésorerie (lignes de
      # banque, de caisse et de Stripe, et leur affectation), les factures
      # d'achat, les notes de frais, la feuille de caisse, les décomptes, les
      # charges récurrentes, le batch cooking et l'arrêté du mois.
      #
      # Chaque écriture passe par le service de l'écran : `Accounting::PostDocument`
      # reste le seul chemin vers le journal, et une correction se contre-passe.
      # Ces écrans sont fermés aux porteurs d'activité restreints : ces outils aussi.
      module Commun
        LIGNE = { type: %w[integer string], description: "Identifiant de la ligne de trésorerie (#5012), rendu par lignes_tresorerie." }.freeze
        FACTURE = { type: %w[integer string], description: "Identifiant de la facture d'achat (#88), rendu par factures_achat." }.freeze
        NOTE = { type: %w[integer string], description: "Note de frais ou de mission : identifiant (#14) ou référence (NF-2026-003)." }.freeze
        MOIS = { type: "string", description: "Mois, AAAA-MM (ex. 2026-09)." }.freeze
        COMPTE_GENERAL = { type: "string", description: "Compte du plan comptable : code (604000) ou partie du nom (« fournitures »)." }.freeze
        POLE = { type: "string", description: "Pôle (nom ou partie du nom). Facultatif : sans pôle, la part reste « non ventilée »." }.freeze
        ENTITE = { type: "string", description: "Entité juridique (nom ou partie : « fondation », « société simple »)." }.freeze
        MONTANT = { type: %w[number string], description: "Montant en euros (« 92,17 »)." }.freeze

        # Les erreurs métier des services de la compta : des refus qu'on
        # explique, pas des pannes. Elles reviennent à Claude telles quelles.
        ESPACES_METIER = %w[Finance:: Accounting:: PurchaseInvoices:: ExpenseReports:: Shop:: CarrierStatements:: Consignments::
                            RevenueShares::].freeze

        module Garde
          def call(arguments)
            if user.restricted_to_own_activities?
              raise Base::Error, "Les finances ne sont pas accessibles à un compte de porteur d'activité, comme dans Claudy."
            end

            super
          end
        end

        def self.included(base)
          base.prepend(Garde)
        end

        private

        def metier!
          yield
        rescue ServiceError, ArgumentError, Date::Error => e
          raise Base::Error, e.message
        rescue ActiveRecord::RecordInvalid => e
          raise Base::Error, e.record.errors.full_messages.to_sentence.presence || e.message
        rescue ActiveRecord::RecordNotUnique
          raise Base::Error, "Déjà enregistré : la base a refusé un doublon, rien n'a été écrit une seconde fois."
        rescue StandardError => e
          raise unless ESPACES_METIER.any? { |espace| e.class.name.to_s.start_with?(espace) }

          raise Base::Error, e.message
        end

        def id!(reference, quoi)
          id = reference.to_s.delete("#").strip
          raise Base::Error, "Identifiant de #{quoi} illisible : « #{reference} »." unless id.match?(/\A\d+\z/)

          id.to_i
        end

        def ligne!(reference)
          raise Base::Error, "Donne la ligne de trésorerie (identifiant)." if reference.blank?

          CashEntry.includes(:cash_account, :cash_motif, cash_allocations: %i[general_account team legal_entity document])
                   .find_by(id: id!(reference, "ligne")) ||
            raise(Base::Error, "Aucune ligne de trésorerie ##{reference.to_s.delete('#')}.")
        end

        def facture!(reference)
          raise Base::Error, "Donne la facture (identifiant)." if reference.blank?

          PurchaseInvoice.includes(:third_party, :legal_entity, :validation_team, purchase_invoice_lines: %i[general_account team])
                         .find_by(id: id!(reference, "facture")) ||
            raise(Base::Error, "Aucune facture d'achat ##{reference.to_s.delete('#')}.")
        end

        def note!(reference)
          texte = reference.to_s.strip
          raise Base::Error, "Donne la note (identifiant ou référence)." if texte.empty?

          scope = ExpenseReport.includes(:human, :legal_entity, expense_lines: %i[general_account team])
          note = texte.delete("#").match?(/\A\d+\z/) ? scope.find_by(id: texte.delete("#")) : scope.find_by("reference ILIKE ?", texte)
          note || raise(Base::Error, "Aucune note de frais « #{texte} ».")
        end

        # Une facture de vente par son #id, ou par son numéro (unique par entité :
        # deux entités portant le même numéro, on refuse et on les liste).
        def facture_vente!(reference)
          texte = reference.to_s.strip
          raise Base::Error, "Donne la facture de vente (#id ou numéro)." if texte.empty?

          scope = SalesInvoice.includes(:customer, :legal_entity, sales_invoice_sources: :source)
          return scope.find_by(id: texte.delete("#")) || raise(Base::Error, "Aucune facture de vente #{texte}.") if texte.start_with?("#")

          trouvees = scope.where(number: texte).to_a
          trouvees = scope.where(id: texte).to_a if trouvees.empty? && texte.match?(/\A\d+\z/)
          return trouvees.first if trouvees.one?
          raise Base::Error, "Aucune facture de vente « #{texte} »." if trouvees.empty?

          raise Base::Error, "Plusieurs factures portent le numéro #{texte} : #{trouvees.map { |f| "##{f.id} (#{f.legal_entity&.name})" }.join(', ')}."
        end

        # Le plan comptable : un code exact d'abord, sinon le nom.
        def compte_general!(reference)
          texte = reference.to_s.strip
          raise Base::Error, "Précise le compte (code ou nom)." if texte.empty?

          par_code = GeneralAccount.actives.find_by(code: texte)
          return par_code if par_code

          trouves = GeneralAccount.actives.where("code LIKE :debut OR name ILIKE :m",
                                                 debut: "#{GeneralAccount.sanitize_sql_like(texte)}%",
                                                 m: "%#{GeneralAccount.sanitize_sql_like(texte)}%").ordered.to_a
          return trouves.first if trouves.one?
          raise Base::Error, "Aucun compte actif du plan ne correspond à « #{texte} »." if trouves.empty?

          raise Base::Error, "Plusieurs comptes correspondent à « #{texte} » : " \
                             "#{trouves.first(12).map(&:to_s).join(', ')}#{' …' if trouves.size > 12}. Donne le code."
        end

        def par_nom!(scope, reference, quoi)
          texte = reference.to_s.strip.delete_prefix("#")
          raise Base::Error, "Précise #{quoi}." if texte.empty?
          return scope.find_by(id: texte) || raise(Base::Error, "Aucun·e #{quoi} ##{texte}.") if texte.match?(/\A\d+\z/)

          trouves = scope.where("#{scope.table_name}.name ILIKE ?", "%#{scope.sanitize_sql_like(texte)}%").to_a
          exact = trouves.find { |r| r.name.casecmp?(texte) }
          return exact if exact
          return trouves.first if trouves.one?
          raise Base::Error, "Aucun·e #{quoi} ne correspond à « #{texte} »." if trouves.empty?

          raise Base::Error, "Plusieurs (#{quoi}) correspondent à « #{texte} » : #{trouves.first(12).map(&:name).join(', ')}."
        end

        def pole!(reference) = par_nom!(Team.all, reference, "pôle")
        def entite!(reference) = par_nom!(LegalEntity.actives, reference, "entité")
        def tiers!(reference) = par_nom!(ThirdParty.actives, reference, "tiers")
        def compte_tresorerie!(reference) = par_nom!(CashAccount.actives, reference, "compte de trésorerie")

        def analytique!(reference)
          texte = reference.to_s.strip
          AnalyticAccount.actives.find_by(code: texte) || par_nom!(AnalyticAccount.actives, texte, "compte analytique")
        end

        # La caisse ACTIVE, comme la feuille de caisse : celle qu'on nomme, ou
        # la seule qui existe.
        def caisse!(reference = nil)
          caisses = CashAccount.actives.where(kind: "cash").ordered
          return par_nom!(caisses, reference, "caisse") if reference.present?

          caisses.first || raise(Base::Error, "Aucune caisse active.")
        end

        def membre!(reference)
          texte = reference.to_s.strip
          raise Base::Error, "Précise le membre (nom, ou « moi »)." if texte.empty?
          return user.human || raise(Base::Error, "Ton compte n'est rattaché à aucun membre.") if texte.casecmp?("moi")

          par_nom!(Human.all, texte, "membre")
        end

        def mois!(valeur, defaut: nil)
          return defaut if valeur.blank? && defaut

          texte = valeur.to_s.strip
          raise Base::Error, "Mois illisible « #{valeur} » (format AAAA-MM)." unless texte.match?(/\A\d{4}-\d{2}\z/)

          Date.iso8601("#{texte}-01")
        rescue Date::Error
          raise Base::Error, "Mois illisible « #{valeur} » (format AAAA-MM)."
        end

        def nom_mois(mois) = I18n.l(mois, format: "%B %Y")

        # Une période `du` / `au`, l'année civile par défaut, comme les états.
        def periode!(arguments)
          du = arguments["du"].present? ? date!(arguments["du"], "du") : Date.current.beginning_of_year
          au = arguments["au"].present? ? date!(arguments["au"], "au") : Date.current.end_of_year
          raise Base::Error, "La période finit avant de commencer." if au < du

          [du, au]
        end

        def solde_lisible(cents)
          return euros(0) if cents.zero?

          "#{euros(cents.abs)} #{cents.positive? ? 'débiteur' : 'créditeur'}"
        end

        # Un relevé par son #id, ou par sa référence (ACT-12-202607,
        # DV-202608-7, REV-3-202607) : l'identifiant y est toujours.
        def par_reference!(scope, reference, motif, quoi)
          texte = reference.to_s.strip
          raise Base::Error, "Donne #{quoi} (#id ou référence)." if texte.empty?

          id = texte.delete("#")[/\A\d+\z/] || texte[motif, 1]
          raise Base::Error, "Référence illisible : « #{texte} »." if id.nil?

          scope.find_by(id: id) || raise(Base::Error, "Introuvable : #{quoi} « #{texte} ».")
        end

        def releve_porteur!(reference)
          par_reference!(CarrierStatement.includes(:human), reference, /\AACT-(\d+)/i, "le relevé de porteur")
        end

        def ligne_releve_porteur(r)
          "Relevé ##{r.id} #{r.reference} · #{r.human&.name} · du #{r.period_from} au #{r.period_to} · " \
            "#{euros(r.total_fee_cents)} · #{r.status_label.downcase}#{' · envoyé' if r.sent_at}"
        end

        # Un relevé de dépôt-vente par `releve`, ou par `artisan` et `mois`.
        def releve_depot_vente!(arguments)
          scope = ConsignmentReport.includes(:consignor, :purchase_invoice, :consignment_report_lines)
          return par_reference!(scope, arguments["releve"], /\ADV-\d{6}-(\d+)/i, "le relevé de dépôt-vente") if arguments["releve"].present?
          raise Base::Error, "Donne le relevé, ou l'artisan et le mois." if arguments["artisan"].blank? || arguments["mois"].blank?

          artisan = par_nom!(Consignor.all, arguments["artisan"], "artisan")
          mois = mois!(arguments["mois"])
          scope.find_by(consignor: artisan, period_month: mois) || raise(Base::Error, "#{artisan.name} n'a pas de relevé pour #{nom_mois(mois)}.")
        end

        def ligne_releve_depot(r)
          "Relevé ##{r.id} #{r.reference} · #{r.consignor&.name} · #{r.period_label} · #{r.status_label.downcase} · " \
            "ventes #{euros(r.displayed_gross_cents)} · commission #{euros(r.displayed_commission_cents)} · net #{euros(r.displayed_net_cents)}" \
            "#{' (totaux du moment)' unless r.frozen_totals?}#{' · demande envoyée' if r.requested? && r.requested_at}"
        end

        # Un accord de partage : #id, hébergement ou bénéficiaire.
        def accord_partage!(reference)
          texte = reference.to_s.strip.delete_prefix("#")
          raise Base::Error, "Donne l'accord de partage (#id, hébergement ou bénéficiaire)." if texte.empty?

          scope = RevenueShareAgreement.includes(:lodging, :beneficiary_third_party)
          return scope.find_by(id: texte) || raise(Base::Error, "Aucun accord de partage ##{texte}.") if texte.match?(/\A\d+\z/)

          motif = "%#{RevenueShareAgreement.sanitize_sql_like(texte)}%"
          trouves = scope.left_joins(:lodging).where("lodgings.name ILIKE :m OR revenue_share_agreements.beneficiary_name ILIKE :m", m: motif).to_a
          return trouves.first if trouves.one?
          raise Base::Error, "Aucun accord de partage ne correspond à « #{texte} »." if trouves.empty?

          raise Base::Error, "Plusieurs accords correspondent à « #{texte} » : #{trouves.map { |a| "##{a.id} #{a.lodging&.name} (#{a.beneficiary_name})" }.join(', ')}."
        end

        def releve_partage!(reference)
          par_reference!(RevenueShareStatement.includes(revenue_share_agreement: :lodging), reference, /\AREV-(\d+)/i, "le relevé de partage")
        end

        def ligne_accord(a)
          "Accord ##{a.id} #{a.lodging&.name || 'hébergement supprimé'} → #{a.beneficiary_name} · #{a.share_percent} % · " \
            "#{a.period_label.downcase} · dès le #{a.starts_on}#{" jusqu'au #{a.ends_on}" if a.ends_on}#{' · INACTIF' unless a.active?}"
        end

        def ligne_releve_partage(r)
          "Relevé ##{r.id} #{r.reference} · #{r.revenue_share_agreement.lodging&.name} · #{r.period_label} · base #{euros(r.base_cents)} · " \
            "part #{euros(r.share_cents)} · #{r.status_label.downcase}#{" le #{r.paid_on}" if r.paid? && r.paid_on}#{' · envoyé' if r.sent_at}"
        end

        # Le paramétrage se règle aussi sur une entité désactivée.
        def entite_meme_inactive!(reference) = par_nom!(LegalEntity.all, reference, "entité")

        def ligne_exercice(y)
          "Exercice ##{y.id} #{y.label} · #{y.legal_entity&.name} · du #{y.starts_on} au #{y.ends_on} · #{y.status_label.downcase}"
        end

        def echeance!(reference)
          raise Base::Error, "Donne l'échéance (#id, rendu par echeancier)." if reference.blank?

          ComplianceDeadline.includes(:purchase_invoice, compliance_obligation: :legal_entity).find_by(id: id!(reference, "échéance")) ||
            raise(Base::Error, "Aucune échéance ##{reference.to_s.delete('#')}.")
        end

        def ligne_echeance(d)
          "Échéance ##{d.id} #{d.display_title} · #{d.legal_entity.name} · pour le #{d.due_on} · #{d.status_label.downcase}" \
            "#{" (le #{d.effective_done_on})" if d.closed? && d.effective_done_on}#{' · EN RETARD' if d.overdue?}" \
            "#{' · paiement' if d.payment?}#{" · facture ##{d.purchase_invoice_id}" if d.purchase_invoice_id}"
        end

        # La page à jeton d'un relevé (porteur, artisan, bénéficiaire), à
        # partager à la main quand personne n'a d'adresse email.
        def lien_public(route, token)
          options = ActionMailer::Base.default_url_options
          helpers = Rails.application.routes.url_helpers
          options[:host].present? ? helpers.public_send("#{route}_url", token, **options) : helpers.public_send("#{route}_path", token)
        end

        def contrepartie(entry)
          [entry.counterparty_name.presence, entry.communication.presence && "« #{entry.communication.to_s.squish.truncate(90)} »"]
            .compact.join(" ").presence || entry.label
        end

        def ligne_tresorerie(entry)
          reste = entry.remaining_cents
          etat = case entry.status
                 when "excluded" then "exclue (#{entry.excluded_reason})"
                 when "allocated" then entry.posted? ? "affectée, comptabilisée" : "affectée"
                 else reste == entry.amount_cents ? "à affecter" : "à affecter, reste #{euros(reste)}"
                 end
          "Ligne ##{entry.id}  #{entry.entry_date}  #{euros(entry.amount_cents).rjust(11)}  #{entry.cash_account&.name} · " \
            "#{contrepartie(entry)} · #{etat}"
        end

        def ligne_affectation(allocation)
          details = ["affectation ##{allocation.id} #{euros(allocation.amount_cents)} → #{allocation.general_account}"]
          details << "pôle #{allocation.team.name}" if allocation.team
          details << allocation.legal_entity.name if allocation.legal_entity
          details << document_lisible(allocation.document) if allocation.document
          details << "« #{allocation.label} »" if allocation.label.present?
          details.join(" · ")
        end

        def document_lisible(document)
          case document
          when PurchaseInvoice then "facture d'achat ##{document.id} #{document.reference}"
          when ExpenseReport then "#{document.kind_label.downcase} #{document.reference || "##{document.id}"}"
          when MemberAccount then "compte #{document.code} #{document.name}"
          when Stay then "séjour ##{document.id}"
          when SalesInvoice then "facture de vente #{document.number}"
          when Event then "événement ##{document.id} #{document.name}"
          when nil then nil
          else "#{document.class.model_name.human} ##{document.id}"
          end
        end

        # Une règle d'affectation en une ligne : ses critères, ce qu'elle propose.
        def ligne_regle(regle)
          criteres = []
          criteres << "IBAN #{regle.counterparty_iban}" if regle.counterparty_iban.present?
          criteres << "tiers ~ « #{regle.counterparty_name_contains} »" if regle.counterparty_name_contains.present?
          criteres << "communication ~ « #{regle.communication_contains} »" if regle.communication_contains.present?
          criteres << "code #{regle.transaction_code}" if regle.transaction_code.present?
          criteres << regle.direction_label.downcase if regle.direction.present?
          criteres << "au moins #{euros(regle.min_amount_cents)}" if regle.min_amount_cents
          criteres << "au plus #{euros(regle.max_amount_cents)}" if regle.max_amount_cents
          criteres << "compte #{regle.cash_account.name}" if regle.cash_account
          propose = [regle.general_account.to_s, regle.team&.name, regle.legal_entity&.name,
                     regle.analytic_account && "analytique #{regle.analytic_account.code}",
                     regle.event && "événement ##{regle.event_id} #{regle.event.name}"].compact.join(" · ")
          "Règle ##{regle.id} « #{regle.label} »#{' (inactive)' unless regle.active?} · ordre #{regle.position} · " \
            "#{criteres.join(', ')} → #{propose} · confiance #{regle.confidence} % · " \
            "#{regle.accepted_count} acceptée(s) / #{regle.rejected_count} refusée(s)"
        end

        def regle!(reference)
          texte = reference.to_s.strip.delete_prefix("#")
          raise Base::Error, "Donne la règle (identifiant ou nom)." if texte.empty?
          return AllocationRule.find_by(id: texte) || raise(Base::Error, "Aucune règle ##{texte}.") if texte.match?(/\A\d+\z/)

          trouvees = AllocationRule.where("label ILIKE ?", "%#{AllocationRule.sanitize_sql_like(texte)}%").ordered.to_a
          exacte = trouvees.find { |r| r.label.casecmp?(texte) }
          return exacte if exacte
          return trouvees.first if trouvees.one?
          raise Base::Error, "Aucune règle ne correspond à « #{texte} »." if trouvees.empty?

          raise Base::Error, "Plusieurs règles correspondent à « #{texte} » : " \
                             "#{trouvees.first(12).map { |r| "##{r.id} #{r.label}" }.join(', ')}."
        end

        # Une dette ou un litige sans facture (`Liability`) en une ligne.
        def ligne_dette(dette)
          fourchette = dette.ranged? ? " · fourchette #{dette.low_cents ? euros(dette.low_cents) : '?'} – #{dette.high_cents ? euros(dette.high_cents) : '?'}" : ""
          quand = if dette.expected_on.nil? then "sans date (comptée aujourd'hui)"
                  elsif dette.installments > 1 then "#{dette.installments} mensualités dès le #{dette.expected_on}"
                  else "le #{dette.expected_on}"
                  end
          "Dette ##{dette.id} #{dette.label} (#{dette.kind_label.downcase}, #{dette.legal_entity.name}" \
            "#{", #{dette.third_party.name}" if dette.third_party}) · #{dette.status_label.downcase}" \
            "#{" · réclamé #{euros(dette.claimed_cents)}" if dette.claimed_cents}#{fourchette} · retenu #{euros(dette.retained_cents)}" \
            "#{" · déjà payé #{euros(dette.paid_cents)}" if dette.paid_cents.positive?} · #{quand}"
        end

        def ligne_facture(facture)
          reste = facture.to_pay? || facture.paid? ? " · reste #{euros(facture.remaining_cents)}" : ""
          "Facture ##{facture.id} #{facture.third_party&.name}#{" n° #{facture.number}" if facture.number.present?} · " \
            "#{euros(facture.total_cents)} · du #{facture.issued_on}#{" · échéance #{facture.due_on}" if facture.due_on} · " \
            "#{facture.status_label}#{reste} · #{facture.legal_entity&.name}"
        end

        def ligne_note(note)
          "#{note.kind_label} ##{note.id}#{" #{note.reference}" if note.reference.present?} · #{note.human&.name} · " \
            "#{euros(note.total_cents)} · #{note.status_label}#{" (#{note.rejection_reason})" if note.rejected?}" \
            "#{" · reste #{euros(note.remaining_cents)}" if note.processing?}"
        end

        def etat_de(record)
          [record.class.name, record.id, record.updated_at&.utc&.iso8601(6)]
        end

        # Les arguments qui décident de l'écriture, dans un ordre stable.
        def signature(arguments)
          trier = lambda do |valeur|
            case valeur
            when Hash then valeur.except("motif", "confirmation").sort.to_h { |cle, v| [cle, trier.call(v)] }
            when Array then valeur.map { |v| trier.call(v) }
            else valeur
            end
          end
          trier.call(arguments)
        end
      end
    end
  end
end
