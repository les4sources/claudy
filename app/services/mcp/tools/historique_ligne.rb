module Mcp
  module Tools
    # Qui a créé, modifié ou supprimé une ligne, et quand : l'historique
    # PaperTrail, y compris celui des lignes supprimées.
    class HistoriqueLigne < Base
      tool "historique_ligne",
           title: "Historique d'une ligne",
           description: "L'historique (PaperTrail) d'une ligne de compte : création, modifications, suppression, " \
                        "avec l'auteur et les champs changés. Fonctionne aussi pour une ligne supprimée.",
           schema: {
             properties: { ligne: { type: "integer", description: "Identifiant de la ligne (#id)." } },
             required: ["ligne"]
           }

      def call(arguments)
        id = ids!(arguments["ligne"]).first
        versions = PaperTrail::Version.where(item_type: "AccountEntry", item_id: id).order(:created_at, :id).to_a
        entry = AccountEntry.with_deleted { AccountEntry.find_by(id: id) }
        raise Error, "Aucune ligne ##{id}, ni dans le grand livre ni dans l'historique." if entry.nil? && versions.empty?

        entete = entry ? "#{ligne(entry)}#{' [SUPPRIMÉE]' if entry.deleted_at}" : "Ligne ##{id} (plus en base)"
        return "#{entete}\nAucun historique enregistré." if versions.empty?

        corps = versions.map do |version|
          changements = changements(version).map { |champ, (avant, apres)| "#{champ}: #{avant.inspect} → #{apres.inspect}" }
          "#{version.created_at.in_time_zone.strftime('%Y-%m-%d %H:%M')}  #{version.event}  " \
            "par #{auteur(version.whodunnit)}#{"\n    #{changements.join(' ; ')}" if changements.any?}"
        end
        "#{entete}\n#{corps.join("\n")}"
      end

      private

      IGNORES = %w[id created_at updated_at].freeze

      def changements(version)
        version.changeset.to_h.except(*IGNORES)
      rescue StandardError
        {}
      end

      # `whodunnit` vaut un id d'utilisateur depuis l'interface, un e-mail ou un
      # nom de script ailleurs.
      def auteur(whodunnit)
        return "—" if whodunnit.blank?
        return whodunnit unless whodunnit.to_s.match?(/\A\d+\z/)

        User.find_by(id: whodunnit)&.email || "utilisateur ##{whodunnit}"
      end
    end
  end
end
