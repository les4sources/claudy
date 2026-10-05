module Mcp
  module Tools
    module Sejours
      # « Refuser la demande » (`Stays::Refuser`) : annule, note le motif, et
      # prévient le client — toute la différence avec une simple annulation.
      class RefuserSejour < Ecriture
        include Commun

        tool "refuser_sejour",
             title: "Refuser une demande de séjour",
             description: "Refuse une demande en attente ou pré-confirmée : le séjour est annulé, le motif est ajouté " \
                          "à la note interne, et un email ENVOYÉ AU CLIENT lui explique le refus avec ce motif.",
             schema: {
               properties: {
                 sejour: SEJOUR,
                 raison_client: { type: "string", description: "Le motif du refus, tel que le client le lira dans l'email." }
               },
               required: %w[sejour raison_client]
             }

        def self.transactionnel? = false

        private

        def planifier(arguments)
          stay = sejour!(arguments["sejour"])
          raison = arguments["raison_client"].to_s.strip
          raise Error, "Donne le motif du refus : il est envoyé au client." if raison.empty?
          unless Stays::Refuser::REFUSABLE_STATUSES.include?(stay.status.to_s)
            raise Error, "Seule une demande en attente ou pré-confirmée se refuse (ce séjour est #{statut(stay)})."
          end

          email = email_client(stay)
          Plan.new(
            resume: "#{ligne_sejour(stay)}\nLe séjour sera annulé, motif ajouté à la note interne.\n" \
                    "#{email ? "Email de refus à #{email}" : 'AUCUN email ne pourra partir (client sans adresse) : préviens-le autrement'}" \
                    " — motif : « #{raison} »",
            empreinte: [etat(stay), raison],
            donnees: { stay_id: stay.id, raison: raison }
          )
        end

        def appliquer(plan)
          stay = Stay.find(plan.donnees[:stay_id])
          service = Stays::Refuser.new(stay: stay, reason: plan.donnees[:raison], by: user)
          raise Error, service.error_message unless service.run

          suite = service.email_error ||
                  (service.email_recipient ? "Le client est prévenu (#{service.email_recipient})." : "AUCUN email envoyé : préviens le client autrement.")
          "Demande ##{stay.id} refusée. #{suite}"
        end
      end
    end
  end
end
