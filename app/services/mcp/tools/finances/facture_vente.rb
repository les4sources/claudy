require "base64"

module Mcp
  module Tools
    module Finances
      # Comptabilité > Clients > Ventes (SalesInvoicesController #create,
      # #update et #destroy). Claudy ne produit pas les factures — OkiOki le
      # fait — il les enregistre et dit ce qu'il en reste à encaisser.
      #
      # Deux cas (Michael, 2026-10-30) : la facture d'une réservation de la file
      # Facturation (`SalesInvoices::Register`, sans écriture de vente : la
      # recette arrive à l'encaissement du séjour), et toute autre facture, avec
      # son tiers et ses lignes (`SalesInvoices::Record`, écriture au journal
      # Ventes). Corriger une facture comptabilisée contre-passe et repasse.
      class FactureVente < Ecriture
        include Commun

        GESTES = %w[enregistrer corriger retirer].freeze
        RESERVATIONS = FacturesVente::TYPES.invert.freeze
        TYPES = { "facture" => "invoice", "note_de_credit" => "credit_note" }.freeze
        PDF_MAX = 10.megabytes

        tool "facture_vente",
             title: "Enregistrer, corriger ou retirer une facture de vente",
             description: "enregistrer : une facture émise dans OkiOki. Avec `reservation` (factures_vente a_facturer) : " \
                          "la facture de cette réservation, sans écriture de vente (la recette arrive à l'encaissement du " \
                          "séjour) ; la réservation passe en « facture envoyée ». Sans réservation : `tiers` client et " \
                          "`lignes` (compte 7, montant HT, taux) obligatoires, l'écriture part au journal Ventes (400000 " \
                          "sur le tiers, comptes 7, 451000 si l'entité est assujettie ; la fondation est exemptée, ses " \
                          "lignes sont à 0 %). `type: note_de_credit` passe l'écriture inverse ; avec `facture_corrigee`, " \
                          "elle réduit le reste dû de cette facture. corriger : tout champ ; `lignes` remplace toutes les " \
                          "lignes ; une facture comptabilisée est contre-passée à sa date puis repassée (refusé sur mois " \
                          "arrêté ou exercice clôturé : émets une note de crédit). retirer : la sort du registre (écriture " \
                          "contre-passée), refusé si des lignes bancaires ou une note de crédit y sont liées. `piece_pdf` : " \
                          "le PDF en base64.",
             schema: {
               properties: {
                 geste: { type: "string", enum: GESTES },
                 facture: { type: %w[integer string], description: "Pour corriger ou retirer : la facture (#id ou numéro)." },
                 type: { type: "string", enum: TYPES.keys, description: "Facture (défaut) ou note de crédit." },
                 reservation: { type: %w[integer string], description: "La réservation facturée (séjour #1234…), rendue par factures_vente a_facturer." },
                 type_reservation: { type: "string", enum: RESERVATIONS.keys, description: "Ce qu'est la réservation. Défaut : sejour." },
                 tiers: { type: "string", description: "Sans réservation : le tiers client (nom ou #id, voir tiers)." },
                 lignes: {
                   type: "array",
                   description: "Sans réservation : les lignes de la facture. Leur TTC doit faire le montant.",
                   items: {
                     type: "object",
                     properties: {
                       compte: { type: "string", description: "Compte de produit (classe 7) : code ou nom." },
                       libelle: { type: "string" },
                       montant_ht: MONTANT.merge(description: "Montant HTVA en euros."),
                       taux: { type: "integer", enum: SalesInvoiceLine::VAT_RATES, description: "Taux de TVA. Défaut : 21 si l'entité est assujettie, sinon 0." },
                       tva: MONTANT.merge(description: "La TVA telle que la facture l'affiche. Défaut : calculée."),
                       pole: POLE,
                       analytique: { type: "string", description: "Compte analytique (code ou nom). Facultatif." }
                     },
                     required: %w[compte montant_ht]
                   }
                 },
                 facture_corrigee: { type: %w[integer string], description: "Pour une note de crédit : la facture qu'elle corrige (#id ou numéro)." },
                 numero: { type: "string", description: "Le numéro de la facture dans OkiOki." },
                 date: DATE.merge(description: "Date d'émission. Défaut : aujourd'hui."),
                 montant: MONTANT.merge(description: "Total TTC en euros. Sans réservation, défaut : la somme des lignes."),
                 entite: ENTITE.merge(description: "Entité qui facture. Défaut : la première active."),
                 notes: { type: "string" },
                 piece_pdf: { type: "string", description: "Le PDF de la facture, encodé en base64." },
                 nom_pdf: { type: "string", description: "Nom du fichier PDF. Défaut : <numéro>.pdf." }
               },
               required: %w[geste]
             }

        private

        def planifier(arguments)
          geste = arguments["geste"].to_s
          raise Error, "geste : #{GESTES.join(', ')}." unless GESTES.include?(geste)

          send("plan_#{geste}", arguments)
        end

        def plan_enregistrer(arguments)
          return plan_enregistrer_reservation(arguments) if arguments["reservation"].present?

          numero = arguments["numero"].to_s.strip.presence || raise(Error, "Donne le numéro de la facture (OkiOki).")
          raise Error, "Sans réservation, donne le tiers client (voir l'outil tiers)." if arguments["tiers"].blank?
          entite = arguments["entite"].present? ? entite!(arguments["entite"]) : LegalEntity.actives.ordered.first
          attributs = {
            "legal_entity_id" => entite.id, "third_party_id" => tiers!(arguments["tiers"]).id,
            "kind" => type!(arguments), "number" => numero,
            "issued_on" => (arguments["date"].present? ? date!(arguments["date"], "date") : Date.current).iso8601,
            "notes" => arguments["notes"].to_s.strip.presence,
            "sales_invoice_lines_attributes" => lignes!(arguments["lignes"], entite)
          }
          attributs["credited_invoice_id"] = facture_vente!(arguments["facture_corrigee"]).id if arguments["facture_corrigee"].present?
          attributs["total_cents"] = montant_ou_lignes(arguments, attributs["sales_invoice_lines_attributes"])
          pdf = pdf!(arguments, numero)

          donnees = { geste: "enregistrer_libre", attributs: attributs, pdf: pdf }
          apres = simuler { enregistrer_libre(donnees, "claude:#{user.email}") }
          Plan.new(resume: "Nouvelle #{attributs['kind'] == 'credit_note' ? 'note de crédit' : 'facture de vente'} : #{apres}",
                   empreinte: [attributs, pdf&.dig(:sha)], donnees: donnees)
        end

        def plan_enregistrer_reservation(arguments)
          raise Error, "Une note de crédit ne se rattache pas à une réservation." if type!(arguments) == "credit_note"

          cle = arguments["type_reservation"].presence || (arguments["type"] if RESERVATIONS.key?(arguments["type"])) || "sejour"
          kind = RESERVATIONS[cle] || raise(Error, "type_reservation : #{RESERVATIONS.keys.join(', ')}.")
          source = Invoicing::Queue.model_for(kind).find_by(id: id!(arguments["reservation"], "réservation")) ||
                   raise(Error, "Aucun·e #{cle} ##{arguments['reservation'].to_s.delete('#')}.")
          numero = arguments["numero"].to_s.strip.presence || raise(Error, "Donne le numéro de la facture (OkiOki).")
          entite = arguments["entite"].present? ? entite!(arguments["entite"]) : LegalEntity.actives.ordered.first
          montant = arguments["montant"].present? ? cents!(arguments["montant"], "montant").abs : (source.try(:total_amount_cents) || source.try(:price_cents)).to_i
          raise Error, "La réservation n'a pas de montant : donne-le." unless montant.positive?

          donnees = { geste: "enregistrer", kind: kind, source: source.id, entite: entite&.id, numero: numero,
                      date: (arguments["date"].present? ? date!(arguments["date"], "date") : Date.current).iso8601,
                      montant: montant, notes: arguments["notes"].to_s.strip.presence, pdf: pdf!(arguments, numero) }
          apres = simuler { enregistrer(donnees, "claude:#{user.email}") }
          Plan.new(resume: "Nouvelle facture de vente : #{apres}\nLa réservation sort de la file Facturation (facture envoyée). " \
                           "Pas d'écriture de vente : la recette arrive à l'encaissement du séjour.",
                   empreinte: [donnees.except(:pdf), donnees[:pdf]&.dig(:sha), etat_de(source)], donnees: donnees)
        end

        def plan_corriger(arguments)
          facture = facture_vente!(arguments["facture"])
          attributs = {}
          attributs["number"] = arguments["numero"].to_s.strip if arguments["numero"].present?
          attributs["issued_on"] = date!(arguments["date"], "date").iso8601 if arguments["date"].present?
          attributs["total_cents"] = cents!(arguments["montant"], "montant").abs if arguments["montant"].present?
          attributs["legal_entity_id"] = entite!(arguments["entite"]).id if arguments["entite"].present?
          attributs["notes"] = arguments["notes"].to_s.strip.presence if arguments.key?("notes")
          if facture.on_issue?
            attributs["third_party_id"] = tiers!(arguments["tiers"]).id if arguments["tiers"].present?
            attributs["kind"] = type!(arguments) if arguments["type"].present?
            attributs["credited_invoice_id"] = facture_vente!(arguments["facture_corrigee"]).id if arguments["facture_corrigee"].present?
            if arguments["lignes"].present?
              entite = attributs["legal_entity_id"] ? LegalEntity.find(attributs["legal_entity_id"]) : facture.legal_entity
              nouvelles = lignes!(arguments["lignes"], entite)
              attributs["sales_invoice_lines_attributes"] =
                facture.sales_invoice_lines.map { |l| { "id" => l.id, "_destroy" => "1" } } + nouvelles
              attributs["total_cents"] ||= montant_ou_lignes(arguments, nouvelles)
            end
          elsif (%w[tiers lignes type facture_corrigee] & arguments.keys).any?
            raise Error, "Cette facture est celle d'une réservation : seuls le numéro, la date, le montant, l'entité, les notes et le PDF se corrigent."
          end
          pdf = pdf!(arguments, attributs["number"] || facture.number)
          raise Error, "Rien à changer." if attributs.empty? && pdf.nil?

          donnees = { geste: "corriger", id: facture.id, attributs: attributs, pdf: pdf }
          apres = simuler { corriger(donnees, "claude:#{user.email}") }
          resume = ["Corriger : #{ligne_vente(facture)}", "Après : #{apres}"]
          resume << "L'écriture de vente est contre-passée à sa date puis repassée." if facture.posted? && repasse?(attributs)
          Plan.new(resume: resume.join("\n"), empreinte: [etat_de(facture), attributs, pdf&.dig(:sha)], donnees: donnees)
        end

        def plan_retirer(arguments)
          facture = facture_vente!(arguments["facture"])
          raise Error, "Cette facture porte des affectations bancaires : retire-les d'abord (geste_ligne_tresorerie retirer_affectation)." if facture.cash_allocations.any?
          raise Error, "Une note de crédit corrige cette facture : retire-la d'abord." if facture.credit_notes.any?

          suite = if facture.posted?
                    "Son écriture de vente (#{facture.journal_entry&.reference}) est contre-passée à sa date."
                  elsif facture.on_payment?
                    "La réservation reste marquée « facture envoyée »."
                  end
          metier! { simuler { ::SalesInvoices::Withdraw.new(sales_invoice: facture).run! } }
          Plan.new(resume: ["Retirer du registre : #{ligne_vente(facture)}", suite].compact.join("\n"),
                   empreinte: [etat_de(facture)], donnees: { geste: "retirer", id: facture.id })
        end

        def appliquer(plan)
          d = plan.donnees
          case d[:geste]
          when "enregistrer" then "Facture enregistrée : #{enregistrer(d, whodunnit)}"
          when "enregistrer_libre" then "Enregistrée et passée au journal Ventes : #{enregistrer_libre(d, whodunnit)}"
          when "corriger" then "Corrigée : #{corriger(d, whodunnit)}"
          else
            facture = SalesInvoice.find(d[:id])
            metier! { ::SalesInvoices::Withdraw.new(sales_invoice: facture, whodunnit: whodunnit).run! }
            "#{facture.label} retirée du registre."
          end
        end

        def enregistrer(d, auteur)
          service = ::SalesInvoices::Register.new(
            source: Invoicing::Queue.model_for(d[:kind]).find(d[:source]), legal_entity: LegalEntity.find(d[:entite]),
            number: d[:numero], issued_on: Date.iso8601(d[:date]), total_cents: d[:montant], notes: d[:notes],
            document: piece(d[:pdf]), whodunnit: auteur
          )
          metier! { service.run! }
          ligne_vente(service.invoice.reload)
        rescue ::SalesInvoices::Register::AlreadyInvoiced, ::SalesInvoices::Register::UnknownSource => e
          raise Error, e.message
        end

        def enregistrer_libre(d, auteur)
          service = ::SalesInvoices::Record.new(attributes: d[:attributs], document: piece(d[:pdf]), whodunnit: auteur)
          metier! { service.run! }
          ligne_vente(service.invoice)
        rescue ::SalesInvoices::Unpost::Refused => e
          raise Error, e.message
        end

        def corriger(d, auteur)
          service = ::SalesInvoices::Correct.new(sales_invoice: SalesInvoice.find(d[:id]), attributes: d[:attributs],
                                                 document: piece(d[:pdf]), whodunnit: auteur)
          metier! { service.run! }
          ligne_vente(service.invoice)
        rescue ::SalesInvoices::Correct::Refused, ::SalesInvoices::Unpost::Refused => e
          raise Error, e.message
        end

        def repasse?(attributs)
          (attributs.keys & (::SalesInvoices::Correct::ACCOUNTING_ATTRIBUTES + ["sales_invoice_lines_attributes"])).any?
        end

        def type!(arguments)
          valeur = arguments["type"].presence
          return "invoice" if valeur.nil? || RESERVATIONS.key?(valeur)

          TYPES[valeur] || raise(Error, "type : #{TYPES.keys.join(', ')}.")
        end

        def lignes!(liste, entite)
          raise Error, "Sans réservation, donne les lignes (compte 7, montant_ht, taux)." if liste.blank?
          raise Error, "lignes : une liste d'objets." unless liste.is_a?(Array) && liste.all?(Hash)

          defaut = entite&.vat_regime == "subject" ? 21 : 0
          liste.each_with_index.map do |ligne, index|
            compte = compte_general!(ligne["compte"])
            raise Error, "Ligne #{index + 1} : #{compte} n'est pas un compte de produit (classe 7)." unless compte.klass == 7

            taux = ligne["taux"].presence&.to_i || defaut
            raise Error, "Ligne #{index + 1} : taux #{taux} inconnu (#{SalesInvoiceLine::VAT_RATES.join(', ')})." unless SalesInvoiceLine::VAT_RATES.include?(taux)

            attributs = { "general_account_id" => compte.id, "label" => ligne["libelle"].to_s.strip.presence,
                          "net_cents" => cents!(ligne["montant_ht"], "montant_ht (ligne #{index + 1})"),
                          "vat_rate" => taux, "position" => index }
            attributs["typed_vat_cents"] = cents!(ligne["tva"], "tva (ligne #{index + 1})") if ligne["tva"].present?
            attributs["team_id"] = pole!(ligne["pole"]).id if ligne["pole"].present?
            attributs["analytic_account_id"] = analytique!(ligne["analytique"]).id if ligne["analytique"].present?
            attributs
          end
        end

        # Le montant donné, sinon ce que les lignes font TVA comprise (la TVA
        # d'un taux se calcule sur la somme de ses bases, comme la facture).
        def montant_ou_lignes(arguments, lignes)
          return cents!(arguments["montant"], "montant").abs if arguments["montant"].present?

          lignes.group_by { |l| l["vat_rate"] }.sum do |taux, groupe|
            ht = groupe.sum { |l| l["net_cents"] }
            tva = if groupe.all? { |l| l.key?("typed_vat_cents") }
                    groupe.sum { |l| l["typed_vat_cents"] }
                  else
                    (ht * taux).quo(100).round
                  end
            ht + tva
          end
        end

        def pdf!(arguments, numero)
          return nil if arguments["piece_pdf"].blank?

          octets = begin
            Base64.strict_decode64(arguments["piece_pdf"].to_s.gsub(/\s+/, ""))
          rescue ArgumentError
            raise Error, "piece_pdf n'est pas du base64 lisible."
          end
          raise Error, "piece_pdf n'est pas un PDF (il doit commencer par %PDF)." unless octets.start_with?("%PDF")
          raise Error, "Le PDF dépasse 10 Mo." if octets.bytesize > PDF_MAX

          nom = arguments["nom_pdf"].to_s.strip.presence || "#{numero.to_s.parameterize.presence || 'facture'}.pdf"
          { octets: octets, nom: nom, sha: Digest::SHA256.hexdigest(octets) }
        end

        def piece(pdf)
          return nil if pdf.blank?

          { io: StringIO.new(pdf[:octets]), filename: pdf[:nom], content_type: "application/pdf" }
        end

        def ligne_vente(f)
          "##{f.id || 'nouvelle'} #{f.credit_note? ? 'NC ' : ''}n° #{f.number} · #{f.issued_on} · #{f.customer_name || '—'} · " \
            "#{euros(f.total_cents)} · #{f.status_label.downcase} · #{f.legal_entity&.name}" \
            "#{" · écriture #{f.journal_entry.reference}" if f.journal_entry}"
        end
      end
    end
  end
end
