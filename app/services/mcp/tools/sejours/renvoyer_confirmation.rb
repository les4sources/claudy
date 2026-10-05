module Mcp
  module Tools
    module Sejours
      # Le bouton « Renvoyer l'email de confirmation » de la fiche séjour.
      class RenvoyerConfirmation < Ecriture
        include Commun

        tool "renvoyer_confirmation",
             title: "Renvoyer l'email de confirmation",
             description: "Renvoie AU CLIENT l'email « votre séjour est confirmé » (avec le lien vers sa page de " \
                          "séjour), même s'il est déjà parti : client qui n'a rien reçu ou qui a changé d'adresse.",
             schema: { properties: { sejour: SEJOUR }, required: %w[sejour] }

        def self.transactionnel? = false

        private

        def planifier(arguments)
          stay = sejour!(arguments["sejour"])
          raise Error, "Le séjour n'est pas confirmé (#{statut(stay)})." unless stay.status == "confirmed"

          email = email_client(stay) || raise(Error, "Ce client n'a pas d'adresse e-mail exploitable.")
          deja = stay.confirmation_email_sent_at ? " (déjà envoyé le #{stay.confirmation_email_sent_at.to_date})" : ""
          Plan.new(resume: "#{ligne_sejour(stay)}\nEmail de confirmation à #{email}#{deja}.",
                   empreinte: [etat(stay), stay.confirmation_email_sent_at&.to_i, email],
                   donnees: { stay_id: stay.id })
        end

        def appliquer(plan)
          stay = Stay.find(plan.donnees[:stay_id])
          notifier = Stays::ConfirmationNotifier.new(stay: stay, force: true)
          raise Error, notifier.skip_reason unless notifier.run

          "Email de confirmation envoyé à #{stay.customer.email}."
        end
      end
    end
  end
end
