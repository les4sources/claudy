module Mcp
  module Tools
    module Guide
      # Les chapitres du Guide (Guide::ChaptersController).
      class EnregistrerChapitreGuide < Ecriture
        include Commun

        tool "enregistrer_chapitre_guide",
             title: "Créer, modifier ou supprimer un chapitre du Guide",
             description: "Sans `chapitre` : crée un chapitre (titre, introduction d'une phrase). Avec : le renomme, " \
                          "change son introduction ou sa place dans le sommaire. Avec supprimer (motif obligatoire) : " \
                          "le retire — seulement s'il n'a plus de page. `lecteurs` : les rôles qui lisent le chapitre " \
                          "(les Sourciers lisent tout) ; un nouveau chapitre est lu par tous sauf les porteurs.",
             schema: {
               properties: {
                 chapitre: CHAPITRE,
                 titre: { type: "string" },
                 introduction: { type: "string", description: "Une phrase, affichée sous le titre dans le sommaire." },
                 position: POSITION,
                 lecteurs: { type: "array", items: { type: "string", enum: ::GuideChapter::READER_ROLES },
                             description: "La liste COMPLÈTE des rôles qui lisent le chapitre (porteur = comptes " \
                                          "restreints à leurs activités). Liste vide : les Sourciers seulement." },
                 supprimer: { type: "boolean" }
               }
             }

        private

        def planifier(arguments)
          chapitre = arguments["chapitre"].present? ? chapitre!(arguments["chapitre"]) : nil
          return plan_suppression(chapitre) if arguments["supprimer"]

          attributs = {}
          attributs[:title] = arguments["titre"].to_s.strip if arguments["titre"].present?
          attributs[:description] = arguments["introduction"].to_s.strip.presence if arguments.key?("introduction")
          if arguments.key?("lecteurs")
            lecteurs = Array(arguments["lecteurs"]).map(&:to_s)
            inconnus = lecteurs - ::GuideChapter::READER_ROLES
            raise Error, "Rôle inconnu : #{inconnus.join(', ')} (au choix : #{::GuideChapter::READER_ROLES.join(', ')})." if inconnus.any?

            attributs[:access_roles] = ::GuideChapter::READER_ROLES & lecteurs
          end
          position = arguments["position"].presence&.to_i
          raise Error, "Un nouveau chapitre demande un titre." if chapitre.nil? && attributs[:title].blank?
          raise Error, "Rien à changer." if chapitre && attributs.empty? && position.nil?

          resume = if chapitre
                     ["MODIFIER le chapitre ##{chapitre.id} « #{chapitre.title} »",
                      ("Titre → « #{attributs[:title]} »" if attributs.key?(:title)),
                      ("Introduction → « #{attributs[:description] || '(aucune)'} »" if attributs.key?(:description)),
                      ("Lu par → #{lecteurs_texte(attributs[:access_roles])}" if attributs.key?(:access_roles)),
                      ("Place dans le sommaire → #{position}" if position)].compact.join("\n")
                   else
                     "CRÉER le chapitre « #{attributs[:title]} »#{" — #{attributs[:description]}" if attributs[:description]}" \
                       "#{position ? " en position #{position}" : ', à la fin du sommaire'}, lu par " \
                       "#{lecteurs_texte(attributs.fetch(:access_roles, ::GuideChapter::DEFAULT_READER_ROLES))}."
                   end
          Plan.new(resume: resume, empreinte: [chapitre && [chapitre.id, chapitre.updated_at.to_f], attributs, position],
                   donnees: { chapitre: chapitre&.id, attributs: attributs, position: position })
        end

        def appliquer(plan)
          if plan.donnees[:supprimer]
            chapitre = GuideChapter.find(plan.donnees[:supprimer])
            chapitre.soft_delete!(validate: false)
            return "Chapitre ##{chapitre.id} « #{chapitre.title} » retiré du Guide."
          end

          chapitre = plan.donnees[:chapitre] ? GuideChapter.find(plan.donnees[:chapitre]) : GuideChapter.new
          chapitre.assign_attributes(plan.donnees[:attributs])
          raise Error, chapitre.errors.full_messages.to_sentence unless chapitre.save

          GuideChapter.reorder!(ordre_avec(GuideChapter.ordered.to_a, chapitre, plan.donnees[:position])) if plan.donnees[:position]
          "Chapitre ##{chapitre.id} « #{chapitre.title} » enregistré (#{chapitre.pages.size} page(s))."
        end

        def lecteurs_texte(roles)
          ["les Sourciers", *roles.map { |role| ::Access.label(role) }].join(", ")
        end

        def plan_suppression(chapitre)
          raise Error, "Donne le chapitre à supprimer." unless chapitre
          raise Error, "Le chapitre « #{chapitre.title} » a encore #{chapitre.pages.size} page(s) : déplace-les ou retire-les d'abord." unless chapitre.removable?

          motif!({ "motif" => @motif })
          Plan.new(resume: "SUPPRIMER le chapitre ##{chapitre.id} « #{chapitre.title} » (vide).",
                   empreinte: [chapitre.id, :supprimer], donnees: { supprimer: chapitre.id })
        end
      end
    end
  end
end
