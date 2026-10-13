module Mcp
  module Tools
    module Finances
      # Comptabilité > Boite de réception (MailMessagesController #ignore,
      # #restore et #sync) : sortir un mail de la file, l'y remettre, ou relever
      # la boite. Un mail ne se supprime pas : ignoré, il reste consultable.
      class GesteMailCompta < Ecriture
        include Commun

        GESTES = {
          "ignorer" => "sortir le mail de la file sans facture (publicité, conditions générales, doublon) ; il reste consultable",
          "remettre" => "remettre dans la file un mail ignoré",
          "relever" => "aller chercher tout de suite les nouveaux mails (sans `mail`)"
        }.freeze

        tool "geste_mail_compta",
             title: "Geste sur la boite de réception de la compta",
             description: "#{GESTES.map { |cle, sens| "#{cle} : #{sens}" }.join(' ; ')}. Un mail porteur d'une facture " \
                          "sort de la file en l'encodant (enregistrer_facture_achat `piece_mail`), pas en l'ignorant.",
             schema: {
               properties: {
                 geste: { type: "string", enum: GESTES.keys },
                 mail: { type: %w[integer string], description: "Le mail (#id, rendu par boite_compta)." }
               },
               required: %w[geste]
             }

        # La relève part en tâche de fond : rien à annuler si elle échoue.
        def self.transactionnel? = false

        private

        def planifier(arguments)
          geste = arguments["geste"].to_s
          raise Error, "geste : #{GESTES.keys.join(', ')}." unless GESTES.key?(geste)
          if geste == "relever"
            return Plan.new(resume: "Relever la boite de la compta : les nouveaux mails arrivent d'ici une minute (boite_compta).",
                            empreinte: [geste], donnees: { geste: geste })
          end

          raise Error, "Donne le mail (#id)." if arguments["mail"].blank?

          mail = MailMessage.find_by(id: id!(arguments["mail"], "mail")) || raise(Error, "Aucun mail ##{arguments['mail']}.")
          if geste == "ignorer" && !mail.pending?
            raise Error, "Le mail ##{mail.id} n'est pas à traiter (#{MailMessage::STATUS_LABELS[mail.status].downcase})."
          end
          raise Error, "Le mail ##{mail.id} n'est pas ignoré." if geste == "remettre" && mail.status != "ignored"

          sujet = "Mail ##{mail.id} de #{mail.sender_label} · « #{mail.subject.to_s.squish.truncate(90)} »"
          resume = geste == "ignorer" ? "#{sujet}\nSort de la file à traiter ; il reste consultable dans les ignorés." : "#{sujet}\nRevient dans la file à traiter."
          Plan.new(resume: resume, empreinte: [geste, etat_de(mail)], donnees: { geste: geste, id: mail.id })
        end

        def appliquer(plan)
          case plan.donnees[:geste]
          when "relever"
            MailIntakeJob.perform_later
            "Relève lancée : les nouveaux mails arrivent d'ici une minute."
          when "ignorer"
            MailMessage.find(plan.donnees[:id]).ignore!(user)
            "Mail sorti de la file. Il reste consultable dans les ignorés."
          else
            MailMessage.find(plan.donnees[:id]).restore!
            "Mail remis dans la file à traiter."
          end
        end
      end
    end
  end
end
