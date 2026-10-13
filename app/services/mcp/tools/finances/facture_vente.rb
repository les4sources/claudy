module Mcp
  module Tools
    module Finances
      # Comptabilité > Clients > Ventes (SalesInvoicesController #create,
      # #update et #destroy). Claudy ne produit pas les factures — OkiOki le
      # fait — il les enregistre, les relie à ce qu'elles facturent, et dit
      # lesquelles sont payées. On facture TOUJOURS une réservation précise de
      # la file Facturation, jamais dans le vide (`SalesInvoices::Register`).
      class FactureVente < Ecriture
        include Commun

        GESTES = %w[enregistrer corriger retirer].freeze
        TYPES = FacturesVente::TYPES.invert.freeze

        tool "facture_vente",
             title: "Enregistrer, corriger ou retirer une facture de vente",
             description: "enregistrer : la facture émise dans OkiOki pour une réservation de la file Facturation " \
                          "(factures_vente a_facturer) : `type` et `reservation`, numéro, date, montant (défaut : celui " \
                          "de la réservation), entité ; la réservation passe en « facture envoyée ». corriger : numéro, " \
                          "date, montant, entité ou notes (le lien vers la réservation ne bouge pas, le statut payé se " \
                          "recalcule). retirer : la sort du registre, refusé si des lignes bancaires y sont affectées. " \
                          "Le PDF se joint à l'écran.",
             schema: {
               properties: {
                 geste: { type: "string", enum: GESTES },
                 facture: { type: %w[integer string], description: "Pour corriger ou retirer : la facture (#id ou numéro)." },
                 type: { type: "string", enum: TYPES.keys, description: "Pour enregistrer : ce qu'on facture. Défaut : sejour." },
                 reservation: { type: %w[integer string], description: "Pour enregistrer : le #id de la réservation (séjour #1234…)." },
                 numero: { type: "string", description: "Le numéro de la facture dans OkiOki." },
                 date: DATE.merge(description: "Date d'émission. Défaut : aujourd'hui."),
                 montant: MONTANT.merge(description: "Total TTC en euros."),
                 entite: ENTITE.merge(description: "Entité qui facture. Défaut : la première active."),
                 notes: { type: "string" }
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
          kind = TYPES[arguments["type"].presence || "sejour"] || raise(Error, "type : #{TYPES.keys.join(', ')}.")
          raise Error, "Donne la réservation (#id, rendu par factures_vente a_facturer)." if arguments["reservation"].blank?

          source = Invoicing::Queue.model_for(kind).find_by(id: id!(arguments["reservation"], "réservation")) ||
                   raise(Error, "Aucun·e #{arguments['type'] || 'sejour'} ##{arguments['reservation'].to_s.delete('#')}.")
          numero = arguments["numero"].to_s.strip.presence || raise(Error, "Donne le numéro de la facture (OkiOki).")
          entite = arguments["entite"].present? ? entite!(arguments["entite"]) : LegalEntity.actives.ordered.first
          montant = arguments["montant"].present? ? cents!(arguments["montant"], "montant").abs : (source.try(:total_amount_cents) || source.try(:price_cents)).to_i
          raise Error, "La réservation n'a pas de montant : donne-le." unless montant.positive?

          donnees = { geste: "enregistrer", kind: kind, source: source.id, entite: entite&.id, numero: numero,
                      date: (arguments["date"].present? ? date!(arguments["date"], "date") : Date.current).iso8601,
                      montant: montant, notes: arguments["notes"].to_s.strip.presence }
          apres = simuler { enregistrer(donnees, "claude:#{user.email}") }
          Plan.new(resume: "Nouvelle facture de vente : #{apres}\nLa réservation sort de la file Facturation (facture envoyée).",
                   empreinte: [donnees, etat_de(source)], donnees: donnees)
        end

        def plan_corriger(arguments)
          facture = facture_vente!(arguments["facture"])
          attributs = {}
          attributs[:number] = arguments["numero"].to_s.strip if arguments["numero"].present?
          attributs[:issued_on] = date!(arguments["date"], "date") if arguments["date"].present?
          attributs[:total_cents] = cents!(arguments["montant"], "montant").abs if arguments["montant"].present?
          attributs[:legal_entity_id] = entite!(arguments["entite"]).id if arguments["entite"].present?
          attributs[:notes] = arguments["notes"].to_s.strip.presence if arguments.key?("notes")
          raise Error, "Rien à changer." if attributs.empty?

          apres = simuler { corriger(facture.id, attributs) }
          Plan.new(resume: "Corriger : #{ligne_vente(facture)}\nAprès : #{apres}",
                   empreinte: [etat_de(facture), attributs.transform_values(&:to_s).sort],
                   donnees: { geste: "corriger", id: facture.id, attributs: attributs })
        end

        def plan_retirer(arguments)
          facture = facture_vente!(arguments["facture"])
          if facture.cash_allocations.any?
            raise Error, "Cette facture porte des affectations bancaires : retire-les d'abord (geste_ligne_tresorerie retirer_affectation)."
          end

          Plan.new(resume: "Retirer du registre : #{ligne_vente(facture)}\nLa réservation reste marquée « facture envoyée ».",
                   empreinte: [etat_de(facture)], donnees: { geste: "retirer", id: facture.id })
        end

        def appliquer(plan)
          d = plan.donnees
          case d[:geste]
          when "enregistrer" then "Facture enregistrée : #{enregistrer(d, whodunnit)}"
          when "corriger" then "Facture corrigée : #{corriger(d[:id], d[:attributs])}"
          else
            facture = SalesInvoice.find(d[:id])
            facture.destroy
            "Facture #{facture.number} retirée du registre."
          end
        end

        def enregistrer(d, auteur)
          service = ::SalesInvoices::Register.new(
            source: Invoicing::Queue.model_for(d[:kind]).find(d[:source]), legal_entity: LegalEntity.find(d[:entite]),
            number: d[:numero], issued_on: Date.iso8601(d[:date]), total_cents: d[:montant], notes: d[:notes], whodunnit: auteur
          )
          metier! { service.run! }
          ligne_vente(service.invoice.reload)
        rescue ::SalesInvoices::Register::AlreadyInvoiced, ::SalesInvoices::Register::UnknownSource => e
          raise Error, e.message
        end

        def corriger(id, attributs)
          facture = SalesInvoice.find(id)
          metier! { facture.update!(attributs) }
          # Le montant a pu changer : payée ou émise se recalcule sur les
          # affectations bancaires, jamais d'après l'ancien total.
          ::SalesInvoices::RefreshPayment.new(sales_invoice: facture).run!
          ligne_vente(facture.reload)
        end

        def ligne_vente(f)
          "##{f.id || 'nouvelle'} n° #{f.number} · #{f.issued_on} · #{f.customer_name || '—'} · #{euros(f.total_cents)} · " \
            "#{f.status_label.downcase} · #{f.legal_entity&.name}"
        end
      end
    end
  end
end
