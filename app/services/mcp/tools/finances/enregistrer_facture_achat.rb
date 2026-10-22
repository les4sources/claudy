module Mcp
  module Tools
    module Finances
      # Encoder ou corriger une facture d'achat (PurchaseInvoicesController
      # #create et #update) : fournisseur, entité, montant, échéance, et les
      # lignes qui la ventilent par compte de charge et par pôle.
      #
      # La pièce PDF ne transite pas par le connecteur. Pour une pièce arrivée
      # dans la boite `compta@`, `piece_mail` encode la facture depuis le PDF
      # déjà en base, comme « Créer la facture » à l'écran
      # (`PurchaseInvoices::FromMailAttachment`). Sinon la facture garde le
      # défaut « no_document » tant que le PDF n'est pas déposé dans Claudy.
      class EnregistrerFactureAchat < Ecriture
        include Commun

        LIGNE_FACTURE = {
          type: "object",
          additionalProperties: false,
          properties: {
            compte: COMPTE_GENERAL.merge(description: "Compte de charge (604000, « entretien »…)."),
            montant: MONTANT,
            pole: POLE,
            analytique: { type: "string", description: "Compte analytique (code ou nom), facultatif." },
            libelle: { type: "string" }
          },
          required: %w[compte montant]
        }.freeze

        tool "enregistrer_facture_achat",
             title: "Encoder ou corriger une facture d'achat",
             description: "Crée une facture fournisseur (« à traiter »), ou corrige une facture qui n'est pas encore " \
                          "« à payer ». Les lignes ventilent le total par compte de charge et par pôle ; données en " \
                          "correction, elles REMPLACENT toutes les lignes. `validation` désigne le pôle qui doit dire " \
                          "oui avant le paiement (« aucune » pour retirer). Ensuite : geste_facture_achat soumettre. " \
                          "Pour une pièce de la boite compta@ (boite_compta) : `piece_mail` reprend ce que la lecture " \
                          "du mail a trouvé (fournisseur, numéro, total, dates, communication ; les arguments donnés " \
                          "l'emportent), joint son PDF et classe le mail. Sinon la pièce PDF se dépose dans Claudy.",
             schema: {
               properties: {
                 facture: FACTURE.merge(description: "Pour corriger : la facture (#88). Absente : nouvelle facture."),
                 piece_mail: { type: %w[integer string], description: "Nouvelle facture depuis une pièce de la boite compta@ (#id de pièce, rendu par boite_compta)." },
                 fournisseur: { type: "string", description: "Le tiers fournisseur (nom ou code), voir referentiel_comptable tiers." },
                 entite: ENTITE.merge(description: "Entité qui doit la facture. Défaut : la fondation."),
                 numero: { type: "string" },
                 date: DATE.merge(description: "Date de la facture. Défaut : aujourd'hui."),
                 echeance: DATE.merge(description: "Date d'échéance."),
                 total: MONTANT.merge(description: "Total TTC en euros."),
                 communication: { type: "string", description: "Communication de paiement (structurée +++…+++ ou libre)." },
                 validation: { type: "string", description: "Pôle qui valide avant paiement, ou « aucune »." },
                 notes: { type: "string" },
                 lignes: { type: "array", items: LIGNE_FACTURE }
               }
             }

        private

        def planifier(arguments)
          facture = arguments["facture"].present? ? facture!(arguments["facture"]) : nil
          raise Error, "piece_mail sert à créer une facture, pas à en corriger une." if facture && arguments["piece_mail"].present?

          @piece = piece_mail!(arguments["piece_mail"]) if arguments["piece_mail"].present?
          if facture&.frozen_content?
            raise Error, "Cette facture est #{facture.status_label.downcase} : son écriture est passée, elle se corrige par contre-passation."
          end
          raise Error, "Cette facture est payée par un membre : rouvre-la (geste_facture_achat rouvrir) pour la corriger." if facture&.member_paid?

          attributs = attributs!(arguments, facture)
          raise Error, "Rien à changer." if facture && attributs.empty?

          brouillon = facture ? PurchaseInvoice.find(facture.id) : PurchaseInvoice.new(status: "to_process")
          brouillon.assign_attributes(attributs.except(:lignes))
          total_lignes = attributs[:lignes] ? attributs[:lignes].sum { |l| l[:amount_cents] } : brouillon.lines_total_cents
          ecart = brouillon.total_cents.to_i - total_lignes

          resume = [facture ? "Corriger #{ligne_facture(facture)}" : "Nouvelle facture d'achat (à traiter)"]
          resume << "Fournisseur #{brouillon.third_party&.name} · #{brouillon.legal_entity&.name} · n° #{brouillon.number || '—'} · " \
                    "du #{brouillon.issued_on} · échéance #{brouillon.due_on || '—'} · total #{euros(brouillon.total_cents)}"
          resume << "Communication : #{brouillon.payment_reference}" if brouillon.payment_reference.present?
          resume << "Validation par le pôle #{brouillon.validation_team&.name}" if brouillon.requires_validation?
          if attributs[:lignes]
            resume << "Lignes#{' (remplacent les actuelles)' if facture} :"
            resume += attributs[:lignes].map { |l| "  #{decrire_ligne(l)}" }
          end
          resume << (ecart.zero? ? "Les lignes couvrent le total." : "⚠ Il reste #{euros(ecart)} à ventiler avant de soumettre au paiement.")
          if (doublon = doublon(brouillon))
            raise Error, "Ce numéro existe déjà pour ce fournisseur : facture ##{doublon.id}."
          end
          if @piece
            resume << "Pièce : « #{@piece.filename} » du mail de #{@piece.mail_message.sender_label} " \
                      "(« #{@piece.mail_message.subject} ») ; le mail sera classé."
          elsif !facture&.document&.attached?
            resume << "La pièce PDF est à déposer dans Claudy."
          end

          Plan.new(resume: resume.join("\n"), empreinte: [facture && etat_de(facture), @piece && etat_de(@piece), signature(arguments)],
                   donnees: { id: facture&.id, attributs: attributs, piece: @piece&.id })
        end

        def appliquer(plan)
          attributs = plan.donnees[:attributs]
          facture = plan.donnees[:id] ? PurchaseInvoice.find(plan.donnees[:id]) : PurchaseInvoice.new
          facture.assign_attributes(attributs.except(:lignes))
          if attributs[:lignes]
            existantes = facture.purchase_invoice_lines.map { |l| { id: l.id, _destroy: "1" } }
            facture.purchase_invoice_lines_attributes = existantes + attributs[:lignes].each_with_index.map { |l, i| l.merge(position: i) }
          end
          piece = plan.donnees[:piece] && ::PurchaseInvoices::FromMailAttachment.new(MailAttachment.find(plan.donnees[:piece]))
          piece&.attach_document(facture)
          metier! { facture.save! }
          piece&.settle!(facture, user)
          "Facture enregistrée : #{ligne_facture(facture.reload)}#{"\nMail classé." if piece&.attachment&.mail_message&.reload&.status == 'filed'}"
        end

        def attributs!(arguments, facture)
          a = @piece ? depuis_mail(@piece) : {}
          a[:third_party_id] = tiers!(arguments["fournisseur"]).id if arguments["fournisseur"].present?
          if facture.nil? && a[:third_party_id].nil?
            raise Error, @piece ? "La lecture du mail n'a pas reconnu le fournisseur : donne-le (créé au besoin avec enregistrer_tiers)." : "Donne le fournisseur."
          end

          if arguments["entite"].present?
            a[:legal_entity_id] = entite!(arguments["entite"]).id
          elsif facture.nil? && a[:legal_entity_id].nil?
            entite = LegalEntity.actives.ordered.find_by("name ILIKE ?", "%fondation%") || LegalEntity.actives.ordered.first
            a[:legal_entity_id] = entite&.id || raise(Error, "Aucune entité juridique active.")
          end
          a[:number] = arguments["numero"].to_s.strip.presence if arguments.key?("numero")
          a[:issued_on] = date!(arguments["date"], "date") if arguments["date"].present?
          a[:issued_on] ||= Date.current if facture.nil?
          a[:due_on] = date_ou_nil(arguments["echeance"], "echeance") if arguments.key?("echeance")
          a[:total_cents] = cents!(arguments["total"], "total").abs if arguments["total"].present?
          raise Error, "Donne le total de la facture." if facture.nil? && a[:total_cents].nil?

          a[:payment_reference] = arguments["communication"].to_s.strip.presence if arguments.key?("communication")
          a[:notes] = arguments["notes"].to_s.strip.presence if arguments.key?("notes")
          if arguments["validation"].present?
            if arguments["validation"].to_s.strip.match?(/\A(aucune?|non|personne)\z/i)
              a.merge!(requires_validation: false, validation_team_id: nil)
            else
              a.merge!(requires_validation: true, validation_team_id: pole!(arguments["validation"]).id)
            end
          end
          a[:lignes] = lignes!(arguments["lignes"]) if arguments.key?("lignes")
          a
        end

        # Ce que la lecture du mail propose, pour les champs que l'utilisateur
        # ne donne pas (les arguments explicites écrasent ensuite ces valeurs).
        # Les lignes de TVA proposées n'ont pas de compte : elles restent à
        # ventiler, ici par `lignes` ou à l'écran.
        def depuis_mail(piece)
          brouillon = PurchaseInvoice.new
          ::PurchaseInvoices::FromMailAttachment.new(piece).prefill(brouillon)
          { third_party_id: brouillon.third_party_id, legal_entity_id: brouillon.legal_entity_id, number: brouillon.number,
            total_cents: brouillon.total_cents, issued_on: brouillon.issued_on, due_on: brouillon.due_on,
            payment_reference: brouillon.payment_reference, notes: brouillon.notes }.compact
        end

        def piece_mail!(reference)
          piece = MailAttachment.includes(:mail_message).find_by(id: id!(reference, "pièce"))
          raise Error, "Aucune pièce de mail ##{reference.to_s.delete('#')}." if piece.nil?
          raise Error, "Cette pièce est déjà encodée : facture ##{piece.purchase_invoice_id}." if piece.purchase_invoice_id
          if (deja = piece.existing_invoice)
            raise Error, "Cette pièce correspond déjà à la facture ##{deja.id} (#{deja.third_party&.name} n° #{deja.number})."
          end

          piece
        end

        def lignes!(lignes)
          Array(lignes).each_with_index.map do |ligne, index|
            ligne = ligne.to_h
            {
              general_account_id: compte_general!(ligne["compte"]).id,
              amount_cents: cents!(ligne["montant"], "ligne #{index + 1} montant"),
              team_id: ligne["pole"].present? ? pole!(ligne["pole"]).id : nil,
              analytic_account_id: ligne["analytique"].present? ? analytique!(ligne["analytique"]).id : nil,
              label: ligne["libelle"].to_s.strip.presence
            }
          end
        end

        def decrire_ligne(ligne)
          "#{euros(ligne[:amount_cents])} → #{GeneralAccount.find(ligne[:general_account_id])}" \
            "#{" · pôle #{Team.find(ligne[:team_id]).name}" if ligne[:team_id]}#{" · « #{ligne[:label]} »" if ligne[:label]}"
        end

        def doublon(facture)
          return nil if facture.number.blank? || facture.third_party_id.blank?

          PurchaseInvoice.where(third_party_id: facture.third_party_id, number: facture.number).where.not(id: facture.id).first
        end
      end
    end
  end
end
