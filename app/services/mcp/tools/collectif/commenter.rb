module Mcp
  module Tools
    module Collectif
      # Le fil de commentaires d'un objet (CommentsController#create), avec ses
      # notifications (Notifications::CommentPosted).
      class Commenter < Ecriture
        include Commun

        OBJETS = {
          "rassemblement" => "Gathering", "decision" => "Decision", "sejour" => "Stay",
          "reservation_activite" => "ExperienceBooking", "note_de_frais" => "ExpenseReport",
          "facture_achat" => "PurchaseInvoice", "evenement" => "Event", "caisse" => "CashEntry"
        }.freeze

        tool "commenter",
             title: "Commenter",
             description: "Ajoute un commentaire, signé de ton compte, sur un rassemblement, une décision, un séjour, " \
                          "une réservation d'activité, une note de frais, une facture d'achat, un événement ou une " \
                          "entrée de caisse. Les personnes de la conversation sont NOTIFIÉES (et reçoivent un email " \
                          "si elles l'ont demandé).",
             schema: {
               properties: {
                 sur: { type: "string", enum: OBJETS.keys },
                 identifiant: { type: %w[integer string] },
                 texte: TEXTE
               },
               required: %w[sur identifiant texte]
             }

        def self.transactionnel? = false

        private

        def planifier(arguments)
          type = OBJETS[arguments["sur"].to_s] || raise(Error, "sur : #{OBJETS.keys.join(', ')}.")
          objet = type.constantize.find_by(id: id!(arguments["identifiant"], arguments["sur"])) ||
                  raise(Error, "Aucun(e) #{arguments['sur']} ##{arguments['identifiant']}.")
          texte = arguments["texte"].to_s.strip
          raise Error, "Le commentaire est vide." if texte.empty?

          commentaire = objet.comments.build(author: user, body: html(texte))
          destinataires = Notifications::CommentPosted.new(commentaire).send(:recipients).filter_map { |u| u.human&.name || u.email }
          doublon = objet.comments.where(author: user, created_at: 10.minutes.ago..).find { |c| texte_riche(c.body) == texte_riche(commentaire.body) }
          raise Error, "Ce commentaire vient déjà d'être posté (##{doublon.id})." if doublon

          resume = "Commenter #{arguments['sur']} ##{objet.id} (#{objet.comment_label}) :\n« #{texte} »\n" \
                   "Notifié(s) : #{destinataires.join(', ').presence || 'personne'}."
          Plan.new(resume: resume, empreinte: [type, objet.id, texte],
                   donnees: { type: type, id: objet.id, texte: texte })
        end

        def appliquer(plan)
          objet = plan.donnees[:type].constantize.find(plan.donnees[:id])
          commentaire = objet.comments.create!(author: user, body: html(plan.donnees[:texte]))
          Notifications::CommentPosted.call(commentaire)
          "Commentaire ##{commentaire.id} posté."
        end
      end
    end
  end
end
