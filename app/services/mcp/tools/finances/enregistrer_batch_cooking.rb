module Mcp
  module Tools
    module Finances
      # Saisir, corriger ou supprimer une session de batch cooking
      # (BatchCookingSessionsController) : la session, ses lignes et ses
      # écritures tombent ensemble. Chaque ménage servi est facturé
      # personnes × repas ; chaque cuisinier est crédité de ses portions.
      class EnregistrerBatchCooking < Ecriture
        include Commun

        tool "enregistrer_batch_cooking",
             title: "Enregistrer une session de batch cooking",
             description: "Crée ou corrige une session de batch cooking : date, nombre de repas, PERSONNES servies par " \
                          "compte (`servis` : {\"SRC-0002\": 3}), cuisiniers et leurs portions (`cuisiniers` : " \
                          "{\"Stéphanie\": 6} ; sans portions, partage égal des personnes servies). Les écritures sur " \
                          "les comptes sont recalculées (rejouable) ; une écriture déjà sur un décompte émis bloque la " \
                          "correction. `supprimer: true` retire la session et ses écritures (motif obligatoire).",
             schema: {
               properties: {
                 session: { type: %w[integer string], description: "Pour corriger ou supprimer : la session (#id)." },
                 date: DATE,
                 repas: { type: "integer", description: "Nombre de repas préparés par personne (défaut 5)." },
                 notes: { type: "string" },
                 servis: { type: "object", additionalProperties: { type: "integer" },
                           description: "Compte (code SRC-… ou nom) → nombre de personnes. Donné, il REMPLACE la liste." },
                 cuisiniers: { type: "object", additionalProperties: { type: %w[number string null] },
                               description: "Membre (nom) → portions (null = partage égal). Donné, il REMPLACE la liste." },
                 supprimer: { type: "boolean" }
               }
             }

        private

        def planifier(arguments)
          session = arguments["session"].present? ? session!(arguments["session"]) : nil
          return plan_suppression(session, arguments) if arguments["supprimer"]

          attributs = {}
          attributs[:cooked_on] = date!(arguments["date"], "date") if arguments["date"].present?
          raise Error, "Donne la date de la session." if session.nil? && attributs[:cooked_on].nil?

          attributs[:meals_count] = arguments["repas"].to_i if arguments["repas"].present?
          attributs[:notes] = arguments["notes"].to_s.strip.presence if arguments.key?("notes")
          servis = arguments.key?("servis") ? servis!(arguments["servis"]) : nil
          raise Error, "Donne les comptes servis." if session.nil? && servis.blank?

          cuisiniers = arguments.key?("cuisiniers") ? cuisiniers!(arguments["cuisiniers"]) : nil
          donnees = { id: session&.id, attributs: attributs, servis: servis, cuisiniers: cuisiniers }

          apres = simuler { ecrire(donnees) }
          Plan.new(resume: "#{session ? "Corriger la session ##{session.id} du #{session.cooked_on}" : 'Nouvelle session'}\n#{apres}",
                   empreinte: [session && etat_de(session), signature(arguments)], donnees: donnees)
        end

        def appliquer(plan)
          return supprimer(plan.donnees[:id]) if plan.donnees[:supprimer]

          "Session enregistrée.\n#{ecrire(plan.donnees)}"
        end

        def ecrire(d)
          session = d[:id] ? BatchCookingSession.find(d[:id]) : BatchCookingSession.new(created_by: user, meals_count: 5)
          rapport = metier! do
            session.assign_attributes(d[:attributs])
            session.save!
            synchroniser_servis(session, d[:servis]) if d[:servis]
            synchroniser_cuisiniers(session, d[:cuisiniers]) if d[:cuisiniers]
            ::Finance::RecordBatchCooking.new(session: session.reload, whodunnit: whodunnit).run!
          end
          servis = session.servings.includes(:member_account).map { |s| "#{s.member_account.code} #{s.member_account.name} × #{s.people}" }
          cuistots = session.cooks.includes(:human).map { |c| "#{c.human&.name} #{format('%g', c.portions)} portion(s)" }
          "Session du #{session.cooked_on} · #{session.meals_count} repas · #{session.people_served} personne(s)\n" \
            "  Servis : #{servis.join(', ')}\n  Cuisiniers : #{cuistots.join(', ').presence || 'personne'}\n" \
            "  Écritures : #{rapport.summary}"
        end

        def synchroniser_servis(session, servis)
          voulus = servis.dup
          session.servings.each do |serving|
            personnes = voulus.delete(serving.member_account_id)
            personnes ? serving.update!(people: personnes) : serving.destroy!
          end
          voulus.each { |compte_id, personnes| session.servings.create!(member_account_id: compte_id, people: personnes) }
          session.reload
        end

        def synchroniser_cuisiniers(session, cuisiniers)
          partage = BatchCookingSession.even_split(session.people_served, cuisiniers.size)
          voulus = cuisiniers.each_with_index.to_h { |(human_id, portions), index| [human_id, portions || partage[index]] }
          session.cooks.each do |cook|
            portions = voulus.delete(cook.human_id)
            portions ? cook.update!(portions: portions) : cook.destroy!
          end
          voulus.each { |human_id, portions| session.cooks.create!(human_id: human_id, portions: portions) }
          session.reload
        end

        def servis!(valeur)
          raise Error, "servis : un objet {compte: personnes}." unless valeur.is_a?(Hash)

          valeur.each_with_object({}) do |(reference, personnes), voulus|
            compte = compte!(reference)
            raise Error, "Le compte #{compte.code} est désactivé." unless compte.active?

            n = Integer(personnes.to_s, exception: false)
            raise Error, "servis #{reference} : nombre de personnes illisible « #{personnes} »." if n.nil? || n.negative?

            voulus[compte.id] = n if n.positive?
          end
        end

        def cuisiniers!(valeur)
          raise Error, "cuisiniers : un objet {membre: portions}." unless valeur.is_a?(Hash)

          valeur.each_with_object({}) do |(nom, portions), voulus|
            humain = membre!(nom)
            if portions.nil? || portions.to_s.strip.empty?
              voulus[humain.id] = nil
            else
              texte = portions.to_s.strip.tr(",", ".")
              raise Error, "cuisiniers #{nom} : portions illisibles « #{portions} »." unless texte.match?(/\A\d+(\.\d+)?\z/)

              voulus[humain.id] = BigDecimal(texte)
            end
          end
        end

        def session!(reference)
          BatchCookingSession.find_by(id: id!(reference, "session")) || raise(Error, "Aucune session ##{reference.to_s.delete('#')}.")
        end

        def cles(session) = AccountEntry.unscoped.where("idempotency_key LIKE ?", "#{::Finance::RecordBatchCooking::KEY_PREFIX}:#{session.id}:%")

        def plan_suppression(session, arguments)
          raise Error, "Donne la session à supprimer." if session.nil?

          motif!({ "motif" => @motif })
          ecritures = cles(session).to_a
          raise Error, "Une écriture de cette session est sur un décompte émis : passe par une contre-écriture." if ecritures.any?(&:locked?)

          Plan.new(resume: "SUPPRIMER la session ##{session.id} du #{session.cooked_on} et ses #{ecritures.size} écriture(s) " \
                           "(#{euros(ecritures.select { |e| e.amount_cents.positive? }.sum(&:amount_cents))} facturés).",
                   empreinte: [etat_de(session), ecritures.map(&:id), signature(arguments)],
                   donnees: { id: session.id, supprimer: true })
        end

        def supprimer(id)
          session = BatchCookingSession.find(id)
          metier! do
            cles(session).each(&:destroy!)
            session.soft_delete!(validate: false)
          end
          "Session ##{id} supprimée avec ses écritures."
        end
      end
    end
  end
end
