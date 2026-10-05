module Mcp
  module Tools
    module Sejours
      # La note de la fiche séjour. L'interne n'est jamais montrée au client ;
      # la publique s'affiche sur sa page de séjour.
      class NoterSejour < Ecriture
        include Commun

        tool "noter_sejour",
             title: "Écrire dans la note d'un séjour",
             description: "Ajoute un paragraphe à la note INTERNE d'un séjour (jamais vue du client), ou la remplace. " \
                          "Avec note: \"publique\", écrit la note visible du client sur sa page de séjour (aucun email).",
             schema: {
               properties: {
                 sejour: SEJOUR,
                 texte: { type: "string", description: "Le texte. Vide avec mode « remplacer » : efface la note." },
                 mode: { type: "string", enum: %w[ajouter remplacer], description: "ajouter (défaut) ou remplacer." },
                 note: { type: "string", enum: %w[interne publique], description: "interne (défaut) ou publique." }
               },
               required: %w[sejour texte]
             }

        private

        def planifier(arguments)
          stay = sejour!(arguments["sejour"])
          texte = arguments["texte"].to_s.strip
          remplacer = arguments["mode"] == "remplacer"
          publique = arguments["note"] == "publique"
          raise Error, "Rien à ajouter : le texte est vide." if texte.empty? && !remplacer

          actuel_html = publique ? stay.public_notes.body&.to_html.to_s : Stays::InternalNote.html_for(stay)
          nouveau_html = remplacer ? Stays::InternalNote.to_html(texte) : [actuel_html.presence, Stays::InternalNote.to_html(texte)].compact.join
          nouveau_html = nil unless Stays::InternalNote.present?(nouveau_html)
          avant = Stays::InternalNote.plain_text(actuel_html)
          apres = Stays::InternalNote.plain_text(nouveau_html)
          raise Error, "La note est déjà exactement celle-là." if avant == apres

          Plan.new(
            resume: "#{ligne_sejour(stay)}\nNote #{publique ? 'publique (visible du client)' : 'interne'}, " \
                    "#{remplacer ? 'remplacée' : 'complétée'}.\n\nAvant :\n#{avant.presence || '(vide)'}\n\nAprès :\n#{apres.presence || '(vide)'}",
            empreinte: [etat(stay), avant, apres, publique],
            donnees: { stay_id: stay.id, html: nouveau_html, publique: publique }
          )
        end

        def appliquer(plan)
          stay = Stay.find(plan.donnees[:stay_id])
          champ = plan.donnees[:publique] ? :public_notes : :internal_notes
          stay.update!(champ => plan.donnees[:html])
          "Note #{plan.donnees[:publique] ? 'publique' : 'interne'} du séjour ##{stay.id} enregistrée."
        end
      end
    end
  end
end
