module Mcp
  module Tools
    module Finances
      # Comptabilité > Fournisseurs > Boite de réception (MailMessagesController
      # #index et #show) : les mails arrivés sur `compta@` et ce que la lecture
      # de leurs pièces propose. Un mail sort de la file par une facture
      # encodée (enregistrer_facture_achat `piece_mail`) ou par « ignorer ».
      class BoiteCompta < Base
        include Commun

        STATUTS = { "a_traiter" => "pending", "classes" => "filed", "ignores" => "ignored" }.freeze
        LIMITE = 40
        EXTRAIT = 2_000

        tool "boite_compta",
             title: "Boite de réception de la comptabilité",
             description: "Les mails reçus sur l'adresse de la compta : par défaut ceux « à traiter », avec leurs pièces " \
                          "(#id, nature proposée, fournisseur, numéro, total, dates). Avec `mail` : le détail d'un mail, " \
                          "son texte, et pour chaque pièce ce que la lecture propose, la facture déjà encodée s'il y en " \
                          "a une, et le texte extrait du PDF. Encoder une pièce : enregistrer_facture_achat `piece_mail` ; " \
                          "ignorer ou remettre un mail : geste_mail_compta.",
             schema: {
               properties: {
                 statut: { type: "string", enum: STATUTS.keys, description: "a_traiter (défaut), classes ou ignores." },
                 mail: { type: %w[integer string], description: "Un mail (#id) pour en voir le détail." }
               }
             }

        def call(arguments)
          return detail(id!(arguments["mail"], "mail")) if arguments["mail"].present?

          statut = STATUTS[arguments["statut"].presence || "a_traiter"] || raise(Base::Error, "statut : #{STATUTS.keys.join(', ')}.")
          comptes = MailMessage.group(:status).count
          mails = MailMessage.where(status: statut).recent_first.includes(:mail_attachments).limit(LIMITE).to_a
          entete = STATUTS.map { |cle, valeur| "#{cle.tr('_', ' ')} #{comptes[valeur].to_i}" }.join(" · ")
          return "#{entete}\nAucun mail." if mails.empty?

          "#{entete}\n\n#{mails.map { |m| bloc_mail(m) }.join("\n")}"
        end

        private

        def bloc_mail(mail)
          pieces = mail.mail_attachments.reject(&:embedded_in_id).map { |p| "    #{ligne_piece(p)}" }
          ["Mail ##{mail.id}  #{mail.received_at.to_date}  #{mail.sender_label} · « #{mail.subject.to_s.squish.truncate(90)} »" \
           "#{" · nature proposée : #{mail.triage.dig('nature', 'value')}" if mail.triage.dig('nature', 'value')}",
           *pieces].join("\n")
        end

        def ligne_piece(piece)
          proposition = [MailAttachment::KIND_LABELS[piece.kind],
                         fournisseur(piece),
                         ("n° #{piece.proposed(:number)}" if piece.proposed(:number).present?),
                         (euros(piece.proposed(:total_cents)) if piece.proposed(:total_cents).present?),
                         ("du #{piece.proposed(:issued_on)}" if piece.proposed(:issued_on).present?),
                         ("échéance #{piece.proposed(:due_on)}" if piece.proposed(:due_on).present?),
                         ("communication #{piece.proposed(:payment_reference)}" if piece.proposed(:payment_reference).present?),
                         ("(lu dans la facture électronique)" if piece.from_ubl?)].compact
          deja = piece.purchase_invoice || piece.existing_invoice
          "Pièce ##{piece.id} « #{piece.filename} » : #{proposition.join(' · ').presence || 'aucune proposition'}" \
            "#{" → déjà encodée : facture ##{deja.id}" if deja}"
        end

        def fournisseur(piece)
          tiers = ThirdParty.find_by(id: piece.proposed(:third_party_id)) if piece.proposed(:third_party_id)
          return "fournisseur #{tiers.name}" if tiers

          brouillon = piece.supplier_draft.compact_blank
          return nil if brouillon.empty?

          "fournisseur inconnu de Claudy (#{brouillon.map { |cle, valeur| "#{cle} #{valeur}" }.join(', ')})"
        end

        def detail(id)
          mail = MailMessage.includes(:mail_account, :handled_by, :mail_attachments).find_by(id: id) ||
                 raise(Base::Error, "Aucun mail ##{id}.")
          pieces = mail.mail_attachments.reject(&:embedded_in_id).map do |piece|
            texte = piece.text_content.to_s.squish
            [ligne_piece(piece), ("  Texte du PDF : #{texte.truncate(EXTRAIT)}" if texte.present?)].compact.join("\n")
          end
          [
            "Mail ##{mail.id} reçu le #{I18n.l(mail.received_at, format: :short)} sur #{mail.mail_account&.address}",
            "De : #{mail.sender_label}#{" <#{mail.from_address}>" if mail.from_name.present?}",
            "Objet : #{mail.subject}",
            "Statut : #{MailMessage::STATUS_LABELS[mail.status]}#{" (par #{mail.handled_by.email})" if mail.handled_by}",
            ("Pas de proposition : #{mail.triage['error']}" if mail.triage["error"].present?),
            ("Texte du mail : #{mail.body_text.to_s.squish.truncate(EXTRAIT)}" if mail.body_text.present?),
            (pieces.any? ? pieces.join("\n") : "Aucune pièce jointe.")
          ].compact.join("\n")
        end
      end
    end
  end
end
