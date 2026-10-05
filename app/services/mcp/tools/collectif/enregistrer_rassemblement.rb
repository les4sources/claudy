module Mcp
  module Tools
    module Collectif
      # Créer, modifier ou supprimer un rassemblement (GatheringsController :
      # create, quick_create, update, update_report, destroy).
      class EnregistrerRassemblement < Ecriture
        include Commun

        tool "enregistrer_rassemblement",
             title: "Créer, modifier ou supprimer un rassemblement",
             description: "Sans `rassemblement` : crée un rassemblement d'une catégorie à une date (l'horaire par " \
                          "défaut de la catégorie s'applique si aucune heure n'est donnée). Avec : modifie ce qui est " \
                          "donné (nom, date, heures, lieu, pôles, notes de préparation, compte rendu). Avec supprimer " \
                          "(motif obligatoire) : le supprime avec son ordre du jour et ses actions ; ses décisions restent.",
             schema: {
               properties: {
                 rassemblement: RASSEMBLEMENT,
                 categorie: { type: "string", description: "Catégorie (nom), obligatoire à la création." },
                 nom: { type: "string", description: "Facultatif : sinon « <catégorie> du <date> »." },
                 date: DATE,
                 heure_debut: { type: "string", description: "HH:MM." },
                 heure_fin: { type: "string", description: "HH:MM. Sinon la durée de la catégorie (60 min par défaut)." },
                 lieu: { type: "string" },
                 poles: { type: "array", items: { type: "string" }, description: "Pôles concernés (noms) ; [] = transversal." },
                 notes: TEXTE.merge(description: "Notes de préparation (remplacent les actuelles)."),
                 compte_rendu: TEXTE.merge(description: "Compte rendu (remplace l'actuel)."),
                 supprimer: { type: "boolean" }
               }
             }

        private

        def planifier(arguments)
          gathering = arguments["rassemblement"].present? ? rassemblement!(arguments["rassemblement"]) : nil
          return plan_suppression(gathering) if arguments["supprimer"]

          attributs = gathering ? modification(gathering, arguments) : creation(arguments)
          champs = attributs[:gathering]
          raise Error, "Rien à changer." if champs.except(:starts_at_date, :starts_at_time, :ends_at_date, :ends_at_time).empty? &&
                                            !horaire_change?(gathering, champs) && attributs[:compte_rendu].nil?

          apres = simuler { appliquer_attributs(gathering && Gathering.find(gathering.id), attributs) }
          resume = [gathering ? "Avant : #{ligne_rassemblement(gathering)}" : nil, "#{gathering ? 'Après' : 'Créer'} : #{apres}"]
          resume << "Notes de préparation remplacées." if champs.key?(:notes)
          resume << "Compte rendu remplacé." if attributs[:compte_rendu]
          Plan.new(resume: resume.compact.join("\n"), empreinte: [gathering && etat_de(gathering), signature(arguments)],
                   donnees: { id: gathering&.id, attributs: attributs })
        end

        def appliquer(plan)
          return appliquer_suppression(plan.donnees[:supprimer]) if plan.donnees[:supprimer]

          id = plan.donnees[:id]
          "Rassemblement enregistré : #{appliquer_attributs(id && Gathering.find(id), plan.donnees[:attributs])}"
        end

        def appliquer_attributs(gathering, attributs)
          params = ActionController::Parameters.new(gathering: attributs[:gathering])
          service = gathering ? Gatherings::UpdateService.new(gathering: gathering) : Gatherings::CreateService.new
          service! { service.run!(params) }
          cible = service.gathering
          cible.update!(report: html(attributs[:compte_rendu])) if attributs[:compte_rendu]
          ligne_rassemblement(Gathering.includes(:gathering_category, :teams).find(cible.id))
        rescue ActiveRecord::RecordInvalid => e
          raise Error, e.record.errors.full_messages.to_sentence
        end

        def creation(arguments)
          categorie = categorie!(arguments["categorie"])
          raise Error, "Donne la date du rassemblement." if arguments["date"].blank?

          date = date!(arguments["date"], "date")
          debut = arguments["heure_debut"].present? ? heure!(arguments["heure_debut"], "heure_debut") : categorie.default_start_time&.strftime("%H:%M")
          raise Error, "La catégorie « #{categorie.name} » n'a pas d'horaire par défaut : donne heure_debut." unless debut

          champs = { gathering_category_id: categorie.id, starts_at_date: date.iso8601, starts_at_time: debut }
          champs.merge!(fin(date, debut, arguments["heure_fin"], categorie.default_duration_minutes || 60))
          { gathering: champs.merge(communs(arguments)), compte_rendu: arguments["compte_rendu"].presence }
        end

        def modification(gathering, arguments)
          debut_actuel = gathering.starts_at.in_time_zone
          fin_actuelle = gathering.ends_at.in_time_zone
          date = arguments["date"].present? ? date!(arguments["date"], "date") : debut_actuel.to_date
          debut = arguments["heure_debut"].present? ? heure!(arguments["heure_debut"], "heure_debut") : debut_actuel.strftime("%H:%M")
          duree = ((fin_actuelle - debut_actuel) / 60).round
          champs = { starts_at_date: date.iso8601, starts_at_time: debut }
          champs.merge!(if arguments["heure_fin"].present? || arguments["date"].present? || arguments["heure_debut"].present?
                          fin(date, debut, arguments["heure_fin"], duree)
                        else
                          { ends_at_date: fin_actuelle.to_date.iso8601, ends_at_time: fin_actuelle.strftime("%H:%M") }
                        end)
          champs[:gathering_category_id] = categorie!(arguments["categorie"]).id if arguments["categorie"].present?
          { gathering: champs.merge(communs(arguments)), compte_rendu: arguments.key?("compte_rendu") ? arguments["compte_rendu"].to_s : nil }
        end

        def communs(arguments)
          champs = {}
          champs[:name] = arguments["nom"].to_s.strip if arguments.key?("nom")
          champs[:location] = arguments["lieu"].to_s.strip if arguments.key?("lieu")
          champs[:notes] = html(arguments["notes"]) if arguments.key?("notes")
          champs[:team_ids] = Array(arguments["poles"]).map { |p| pole!(p).id.to_s } if arguments.key?("poles")
          champs
        end

        def fin(date, debut, heure_fin, duree_minutes)
          if heure_fin.present?
            fin = heure!(heure_fin, "heure_fin")
            raise Error, "heure_fin doit suivre heure_debut." if fin <= debut

            { ends_at_date: date.iso8601, ends_at_time: fin }
          else
            fin = Time.zone.parse("#{date.iso8601} #{debut}") + duree_minutes.minutes
            { ends_at_date: fin.to_date.iso8601, ends_at_time: fin.strftime("%H:%M") }
          end
        end

        def horaire_change?(gathering, champs)
          return true unless gathering

          debut = gathering.starts_at.in_time_zone
          fin = gathering.ends_at.in_time_zone
          [champs[:starts_at_date], champs[:starts_at_time], champs[:ends_at_date], champs[:ends_at_time]] !=
            [debut.to_date.iso8601, debut.strftime("%H:%M"), fin.to_date.iso8601, fin.strftime("%H:%M")]
        end

        def categorie!(nom)
          raise Error, "Donne la catégorie du rassemblement." if nom.blank?

          trouves = GatheringCategory.where("name ILIKE ?", "%#{GatheringCategory.sanitize_sql_like(nom.to_s.strip)}%").to_a
          exacte = trouves.find { |c| c.name.casecmp?(nom.to_s.strip) }
          return exacte if exacte
          return trouves.first if trouves.one?
          raise Error, "Aucune catégorie « #{nom} ». Catégories : #{GatheringCategory.order(:name).pluck(:name).join(', ')}." if trouves.empty?

          raise Error, "Plusieurs catégories correspondent à « #{nom} » : #{trouves.map(&:name).join(', ')}."
        end

        def plan_suppression(gathering)
          raise Error, "Donne le rassemblement à supprimer." unless gathering

          motif!({ "motif" => @motif })
          points = gathering.agenda_items.count
          resume = "SUPPRIMER #{ligne_rassemblement(gathering)}\nAvec lui : #{points} point(s) d'ordre du jour, " \
                   "#{gathering.gathering_actions.count} action(s), ses commentaires. " \
                   "#{gathering.decisions.count} décision(s) restent au registre, détachées."
          Plan.new(resume: resume, empreinte: [etat_de(gathering), :supprimer], donnees: { supprimer: gathering.id })
        end

        def appliquer_suppression(id)
          gathering = Gathering.find(id)
          gathering.soft_delete!(validate: false)
          "Rassemblement ##{id} supprimé (suppression douce)."
        end
      end
    end
  end
end
