module Mcp
  module Tools
    module Collectif
      # La fiche du jour (HumanRolesController) et la ligne de garde
      # (OnCallController#phone_holder) : qui tient quel rôle tel jour.
      class AttribuerRole < Ecriture
        include Commun

        STATUTS = { "titulaire" => "selected", "remplacant" => "backup", "aucun" => nil }.freeze

        tool "attribuer_role",
             title: "Attribuer un rôle du jour",
             description: "Met un membre titulaire ou remplaçant d'un rôle (veilleur·euse…) un jour donné, ou le retire " \
                          "(aucun). Pour la veille, `telephone` lui confie aussi le téléphone de la ligne de garde.",
             schema: {
               properties: {
                 membre: MEMBRE,
                 role: { type: "string", description: "Nom du rôle (ex. « veilleur »)." },
                 date: DATE,
                 statut: { type: "string", enum: STATUTS.keys },
                 telephone: { type: "boolean", description: "Titulaire de la veille : il tient le téléphone de garde ce jour-là." }
               },
               required: %w[membre role date statut]
             }

        private

        def planifier(arguments)
          membre = membre!(arguments["membre"])
          role = role!(arguments["role"])
          date = date!(arguments["date"], "date")
          raise Error, "statut : titulaire, remplacant ou aucun." unless STATUTS.key?(arguments["statut"].to_s)

          statut = STATUTS[arguments["statut"].to_s]
          telephone = arguments["telephone"] ? true : false
          raise Error, "Le téléphone de garde va à un titulaire de la veille." if telephone && (statut != "selected" || role.id != OnCall::Resolver::WATCHMAN_ROLE_ID)

          actuel = HumanRole.find_by(human_id: membre.id, role_id: role.id, date: date)
          avant = actuel ? (actuel.selected? ? "titulaire" : "remplaçant") : "rien"
          raise Error, "C'est déjà le cas." if actuel&.status == statut && !(telephone && !actuel.phone_holder?)
          raise Error, "#{membre.name} n'a pas ce rôle ce jour-là." if statut.nil? && actuel.nil?

          autres = HumanRole.includes(:human).where(role_id: role.id, date: date).where.not(human_id: membre.id)
                            .map { |hr| "#{hr.human&.name} (#{hr.selected? ? 'titulaire' : 'remplaçant'})" }
          resume = "#{role.name} le #{I18n.l(date, format: '%a %d/%m/%Y')} : #{membre.name} #{avant} → #{arguments['statut']}" \
                   "#{' et téléphone de garde' if telephone}\nDéjà sur ce rôle ce jour-là : #{autres.join(', ').presence || 'personne'}"
          Plan.new(resume: resume, empreinte: [actuel && [actuel.id, actuel.status, actuel.phone_holder], membre.id, role.id, date.iso8601, statut, telephone],
                   donnees: { human_id: membre.id, role_id: role.id, date: date, statut: statut, telephone: telephone })
        end

        def appliquer(plan)
          d = plan.donnees
          ligne = HumanRole.find_or_initialize_by(human_id: d[:human_id], role_id: d[:role_id], date: d[:date])
          if d[:statut].nil?
            ligne.destroy!
            return "Rôle retiré."
          end

          ligne.update!(status: d[:statut])
          ligne.make_phone_holder! if d[:telephone]
          "Rôle enregistré."
        end

        def role!(nom)
          trouves = Role.where("name ILIKE ?", "%#{Role.sanitize_sql_like(nom.to_s.strip)}%").to_a
          return trouves.first if trouves.one?
          raise Error, "Aucun rôle ne s'appelle « #{nom} ». Rôles : #{Role.order(:name).pluck(:name).join(', ')}." if trouves.empty?

          raise Error, "Plusieurs rôles correspondent à « #{nom} » : #{trouves.map(&:name).join(', ')}."
        end
      end
    end
  end
end
