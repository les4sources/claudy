module Mcp
  module Tools
    module Collectif
      # Les rôles du jour (fiche du jour, ligne de garde) : qui est veilleur,
      # qui est remplaçant, sur une période.
      class RolesDuJour < Base
        include Commun

        tool "roles_du_jour",
             title: "Rôles du jour et ligne de garde",
             description: "Qui tient quel rôle (veilleur·euse et les autres rôles du lieu), titulaire ou remplaçant, " \
                          "jour par jour sur une période (défaut : aujourd'hui et les 6 jours suivants), avec le porteur " \
                          "du téléphone de garde. Liste aussi les rôles existants.",
             schema: { properties: { du: DATE, au: DATE, role: { type: "string", description: "Ne garder que ce rôle (nom)." } } }

        def call(arguments)
          du = date_ou_nil(arguments["du"], "du") || Date.current
          au = date_ou_nil(arguments["au"], "au") || du + 6
          raise Error, "Période trop longue : 62 jours au plus." if (au - du).to_i > 62

          scope = HumanRole.includes(:human, :role).where(date: du..au)
          scope = scope.where(role_id: role!(arguments["role"]).id) if arguments["role"].present?
          par_jour = scope.order(:date, :role_id, :status, :id).group_by(&:date)

          jours = (du..au).map do |jour|
            roles = (par_jour[jour] || []).group_by(&:role).map do |role, lignes|
              titulaires = lignes.select(&:selected?).map { |hr| "#{hr.human&.name}#{' (téléphone)' if hr.phone_holder?}" }
              remplacants = lignes.select(&:backup?).map { |hr| hr.human&.name }
              "#{role.name} : #{titulaires.join(', ').presence || 'personne'}#{" (remplaçant : #{remplacants.join(', ')})" if remplacants.any?}"
            end
            "#{I18n.l(jour, format: '%a %d/%m')} — #{roles.join(' · ').presence || 'aucun rôle'}"
          end
          garde = OnCall::Resolver.new
          [jours.join("\n"),
           "Ligne de garde maintenant (relève à #{OnCall::Config.handover_hour} h) : #{garde.on_call&.name || 'personne de joignable'}" \
           "#{", remplaçant #{garde.backup.name}" if garde.backup}",
           "Rôles : #{Role.order(:name).map(&:name).join(', ').presence || 'aucun'}"].join("\n\n")
        end

        private

        def role!(nom)
          trouves = Role.where("name ILIKE ?", "%#{Role.sanitize_sql_like(nom.to_s.strip)}%").to_a
          return trouves.first if trouves.one?
          raise Error, "Aucun rôle ne s'appelle « #{nom} »." if trouves.empty?

          raise Error, "Plusieurs rôles correspondent à « #{nom} » : #{trouves.map(&:name).join(', ')}."
        end
      end
    end
  end
end
