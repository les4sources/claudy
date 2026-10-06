module Mcp
  module Tools
    module Collectif
      # Ce que partagent les outils de la vie du collectif : rassemblements
      # (réunions, `Gathering`), ordre du jour, décisions, cycles et leurs
      # actions, rôles du jour.
      #
      # Ces écrans sont fermés aux porteurs d'activité restreints
      # (`BaseController::RESTRICTED_ALLOWLIST`) : ces outils aussi.
      module Commun
        RASSEMBLEMENT = { type: %w[integer string], description: "Identifiant du rassemblement (#45), rendu par rassemblements." }.freeze
        DECISION = { type: %w[integer string], description: "Identifiant de la décision (#12), rendu par decisions." }.freeze
        CYCLE = { type: %w[integer string], description: "Cycle : identifiant ou nom. Défaut : le cycle de référence (en cours)." }.freeze
        ACTION_CYCLE = { type: %w[integer string], description: "Identifiant de l'action de cycle (#321), rendu par actions_membre." }.freeze
        MEMBRE = { type: "string", description: "Membre (nom ou partie du nom), ou « moi » pour le compte connecté." }.freeze
        TEXTE = { type: "string", description: "Texte brut ; les retours à la ligne sont gardés." }.freeze

        CATEGORIES = CycleActionDecorator::CATEGORY_STYLES.transform_values { |style| style[:label] }.freeze
        ISSUES = { "done" => "faite", "deferred" => "passée au cycle suivant", "dropped" => "abandonnée" }.freeze

        module Garde
          def call(arguments)
            if user.restricted_to_own_activities?
              raise Base::Error, "La vie du collectif n'est pas accessible à un compte de porteur d'activité, comme dans Claudy."
            end

            super
          end
        end

        def self.included(base)
          base.prepend(Garde)
        end

        private

        def id!(reference, quoi)
          id = reference.to_s.delete("#").strip
          raise Base::Error, "Identifiant de #{quoi} illisible : « #{reference} »." unless id.match?(/\A\d+\z/)

          id.to_i
        end

        def rassemblement!(reference)
          Gathering.includes(:gathering_category, :teams).find_by(id: id!(reference, "rassemblement")) ||
            raise(Base::Error, "Aucun rassemblement ##{reference.to_s.delete('#')}.")
        end

        def decision!(reference)
          Decision.includes(:recorded_by, :gathering).find_by(id: id!(reference, "décision")) ||
            raise(Base::Error, "Aucune décision ##{reference.to_s.delete('#')}.")
        end

        def action_cycle!(reference)
          CycleAction.includes(:human, :cycle, :team).find_by(id: id!(reference, "action")) ||
            raise(Base::Error, "Aucune action de cycle ##{reference.to_s.delete('#')}.")
        end

        def cycle!(reference)
          return Cycle.reference_for || raise(Base::Error, "Aucun cycle n'est configuré.") if reference.blank?

          texte = reference.to_s.strip.delete_prefix("#")
          return Cycle.find_by(id: texte) || raise(Base::Error, "Aucun cycle ##{texte}.") if texte.match?(/\A\d+\z/)

          trouves = Cycle.where("name ILIKE ?", "%#{Cycle.sanitize_sql_like(texte)}%").chronological.to_a
          return trouves.first if trouves.one?
          raise Base::Error, "Aucun cycle ne s'appelle « #{texte} »." if trouves.empty?

          raise Base::Error, "Plusieurs cycles correspondent à « #{texte} » : #{trouves.map { |c| "##{c.id} #{c.name}" }.join(', ')}."
        end

        # Un membre ACTIF (le défaut de `Human`), ou « moi ».
        def membre!(reference)
          reference = reference.to_s.strip
          raise Base::Error, "Précise le membre (nom, ou « moi »)." if reference.empty?
          return moi! if reference.casecmp?("moi")

          humains = Human.where("name ILIKE ?", "%#{Human.sanitize_sql_like(reference)}%").to_a
          exact = humains.find { |h| h.name.casecmp?(reference) }
          return exact if exact
          return humains.first if humains.one?
          raise Base::Error, "Aucun membre actif ne s'appelle « #{reference} »." if humains.empty?

          raise Base::Error, "Plusieurs membres correspondent à « #{reference} » : #{humains.map(&:name).join(', ')}."
        end

        # La personne derrière le compte : auteur d'un point, porteur d'une
        # décision. L'interface retombe sur le premier membre actif quand le
        # compte n'en a pas ; ici on refuse plutôt que de signer au nom d'un autre.
        def moi!
          user.human || raise(Base::Error, "Ton compte Claudy n'est rattaché à aucun membre : ce geste demande un auteur.")
        end

        def pole!(reference)
          texte = reference.to_s.strip.delete_prefix("#")
          return Team.find_by(id: texte) || raise(Base::Error, "Aucun pôle ##{texte}.") if texte.match?(/\A\d+\z/)

          trouves = Team.where("name ILIKE ?", "%#{Team.sanitize_sql_like(texte)}%").to_a
          exact = trouves.find { |t| t.name.casecmp?(texte) }
          return exact if exact
          return trouves.first if trouves.one?
          raise Base::Error, "Aucun pôle ne s'appelle « #{texte} »." if trouves.empty?

          raise Base::Error, "Plusieurs pôles correspondent à « #{texte} » : #{trouves.map(&:name).join(', ')}."
        end

        def heure!(valeur, champ)
          texte = valeur.to_s.strip.tr("h", ":")
          texte = "#{texte}00" if texte.end_with?(":")
          raise Base::Error, "#{champ} : heure illisible « #{valeur} » (ex. 19:30)." unless texte.match?(/\A([01]?\d|2[0-3]):[0-5]\d\z/)

          texte
        end

        # Texte brut → HTML d'un champ riche (Action Text), échappé.
        def html(texte)
          texte.to_s.strip.split(/\n{2,}/).map { |bloc| "<div>#{ERB::Util.html_escape(bloc).gsub("\n", '<br>')}</div>" }.join
        end

        def texte_riche(valeur)
          valeur.respond_to?(:to_plain_text) ? valeur.to_plain_text.strip : valeur.to_s.strip
        end

        def nom_rassemblement(gathering)
          gathering.name.presence || "#{gathering.gathering_category&.name} du #{I18n.l(gathering.starts_at.to_date)}"
        end

        def quand_rassemblement(gathering)
          debut = gathering.starts_at.in_time_zone
          fin = gathering.ends_at.in_time_zone
          "#{I18n.l(debut, format: '%a %d/%m/%Y %H:%M')}–#{fin.to_date == debut.to_date ? I18n.l(fin, format: '%H:%M') : I18n.l(fin, format: '%d/%m %H:%M')}"
        end

        def ligne_rassemblement(gathering)
          poles = gathering.teams.map(&:name)
          "Rassemblement ##{gathering.id} #{nom_rassemblement(gathering)} · #{quand_rassemblement(gathering)} · " \
            "#{gathering.gathering_category&.name}#{" · #{gathering.location}" if gathering.location.present?} · " \
            "#{poles.any? ? "pôles #{poles.join(', ')}" : 'transversal'}"
        end

        def ligne_decision(decision)
          "Décision ##{decision.id} du #{decision.taken_at} : #{decision.title} — #{decision.summary}" \
            "#{" (rassemblement ##{decision.gathering_id})" if decision.gathering_id}"
        end

        def heures(valeur) = "#{format('%g', valeur.to_f.round(2)).tr('.', ',')} h"

        def ligne_action_cycle(action)
          details = ["Action ##{action.id} [#{CATEGORIES.fetch(action.category, action.category)}] #{action.label}"]
          duree = heures(action.hours)
          duree = "#{action.occurrences} × #{heures(action.unit_hours)} = #{duree}" if action.multiple? && action.unit_hours
          details << duree
          details << (action.multiple? ? "fait #{action.completed_occurrences}/#{action.occurrences}" : (action.completed? ? "cochée" : "à faire"))
          details << "réel #{heures(action.actual_hours)}" if action.actual_hours_recorded?
          details << "pôle #{action.team.name}" if action.team
          details << "économique" if action.economic?
          details << "reportée #{action.deferral_count} fois" if action.deferred_before?
          details << ISSUES.fetch(action.outcome, action.outcome) if action.outcome
          details << "archivée" if action.archived?
          details.join(" · ")
        end

        def ouvert!(cycle)
          raise Base::Error, "Le cycle « #{cycle.name} » est clos : il ne se modifie plus." if cycle.closed?
        end

        def etat_de(record)
          [record.class.name, record.id, record.updated_at&.utc&.iso8601(6)]
        end

        # Les arguments qui décident de l'écriture, dans un ordre stable : Claude
        # peut les renvoyer dans un autre ordre à la confirmation.
        def signature(arguments)
          trier = lambda do |valeur|
            case valeur
            when Hash then valeur.except("motif", "confirmation").sort.to_h { |cle, v| [cle, trier.call(v)] }
            when Array then valeur.map { |v| trier.call(v) }
            else valeur
            end
          end
          trier.call(arguments)
        end

        # Les services `ServiceBase` lèvent `ServiceError` pour un refus métier.
        def service!
          yield
        rescue ServiceError => e
          raise Base::Error, e.message
        end
      end
    end
  end
end
